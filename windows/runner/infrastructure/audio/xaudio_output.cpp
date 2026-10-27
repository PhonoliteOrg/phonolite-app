#include "xaudio_output.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <deque>
#include <limits>
#include <memory>
#include <vector>

#include <windows.h>

#include <mmsystem.h>

#include <mmddk.h>
#include <xaudio2.h>

namespace {

constexpr size_t max_queued_buffers = 5;

// A saved picker entry uses a WinMM index. Resolve that exact endpoint rather
// than assuming XAudio2's device ordering matches the existing picker.
HRESULT endpoint_for_device(int32_t device_id, std::vector<wchar_t>& endpoint) {
  if (device_id == -1) {
    return S_OK;
  }
  if (device_id < 0 || static_cast<UINT>(device_id) >= ::waveOutGetNumDevs()) {
    return E_INVALIDARG;
  }

  const auto device = reinterpret_cast<HWAVEOUT>(static_cast<UINT_PTR>(device_id));
  ULONG bytes = 0;
  auto result = ::waveOutMessage(device, DRV_QUERYFUNCTIONINSTANCEIDSIZE, reinterpret_cast<DWORD_PTR>(&bytes), 0);
  if (result != MMSYSERR_NOERROR || bytes < sizeof(wchar_t) || bytes % sizeof(wchar_t) != 0) {
    return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
  }

  endpoint.resize(bytes / sizeof(wchar_t));
  result = ::waveOutMessage(device, DRV_QUERYFUNCTIONINSTANCEID, reinterpret_cast<DWORD_PTR>(endpoint.data()), bytes);
  if (result != MMSYSERR_NOERROR || endpoint.front() == L'\0' || endpoint.back() != L'\0') {
    return HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
  }
  return S_OK;
}

// XAudio2 invokes these on its own render thread. Only the atomic error crosses
// threads; PCM ownership and every engine call remain with the Dart worker.
class AudioErrors final : public IXAudio2EngineCallback, public IXAudio2VoiceCallback {
 public:
  void STDMETHODCALLTYPE OnProcessingPassStart() override {}
  void STDMETHODCALLTYPE OnProcessingPassEnd() override {}
  void STDMETHODCALLTYPE OnCriticalError(HRESULT error) override {
    error_.store(error, std::memory_order_relaxed);
  }
  void STDMETHODCALLTYPE OnVoiceProcessingPassStart(UINT32) override {}
  void STDMETHODCALLTYPE OnVoiceProcessingPassEnd() override {}
  void STDMETHODCALLTYPE OnStreamEnd() override {}
  void STDMETHODCALLTYPE OnBufferStart(void*) override {}
  void STDMETHODCALLTYPE OnBufferEnd(void*) override {}
  void STDMETHODCALLTYPE OnLoopEnd(void*) override {}
  void STDMETHODCALLTYPE OnVoiceError(void*, HRESULT error) override {
    error_.store(error, std::memory_order_relaxed);
  }

  HRESULT failure() const {
    return error_.load(std::memory_order_relaxed);
  }

 private:
  std::atomic<HRESULT> error_{S_OK};
};

class XAudioOutput final {
 public:
  ~XAudioOutput() {
    destroy_source();
    if (mastering_ != nullptr) {
      mastering_->DestroyVoice();
    }
    if (engine_ != nullptr) {
      if (callbacks_registered_) {
        engine_->UnregisterForCallbacks(&errors_);
      }
      engine_->Release();
    }
    if (mta_cookie_ != nullptr) {
      ::CoDecrementMTAUsage(mta_cookie_);
    }
  }

  HRESULT initialize(int32_t sample_rate, int32_t channels, int32_t device_id, int32_t bits_per_sample,
                     int32_t valid_bits_per_sample) {
    if (sample_rate < XAUDIO2_MIN_SAMPLE_RATE || sample_rate > XAUDIO2_MAX_SAMPLE_RATE || channels <= 0 ||
        channels > XAUDIO2_MAX_AUDIO_CHANNELS || (bits_per_sample != 16 && bits_per_sample != 32) ||
        valid_bits_per_sample <= 0 || valid_bits_per_sample > bits_per_sample) {
      return E_INVALIDARG;
    }

    // Dart may resume an isolate on a different pool thread. An MTA usage cookie
    // has cross-thread ownership, unlike a lifetime CoInitializeEx reference.
    auto result = ::CoIncrementMTAUsage(&mta_cookie_);
    if (FAILED(result)) {
      return result;
    }
    result = XAudio2Create(&engine_, 0, XAUDIO2_DEFAULT_PROCESSOR);
    if (FAILED(result)) {
      return result;
    }
    result = engine_->RegisterForCallbacks(&errors_);
    if (FAILED(result)) {
      return result;
    }
    callbacks_registered_ = true;

    std::vector<wchar_t> endpoint;
    result = endpoint_for_device(device_id, endpoint);
    if (FAILED(result)) {
      return result;
    }
    result = engine_->CreateMasteringVoice(&mastering_, XAUDIO2_DEFAULT_CHANNELS, XAUDIO2_DEFAULT_SAMPLERATE, 0,
                                           endpoint.empty() ? nullptr : endpoint.data(), nullptr, AudioCategory_Media);
    if (FAILED(result)) {
      return result;
    }

    auto& format = format_.Format;
    format.wFormatTag = bits_per_sample == 16 && channels <= 2 ? WAVE_FORMAT_PCM : WAVE_FORMAT_EXTENSIBLE;
    format.nChannels = static_cast<WORD>(channels);
    format.nSamplesPerSec = static_cast<DWORD>(sample_rate);
    format.wBitsPerSample = static_cast<WORD>(bits_per_sample);
    format.nBlockAlign = static_cast<WORD>(channels * bits_per_sample / 8);
    format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
    if (format.wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
      format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
      format_.Samples.wValidBitsPerSample = static_cast<WORD>(valid_bits_per_sample);
      format_.dwChannelMask = channels == 1   ? SPEAKER_FRONT_CENTER
                              : channels == 2 ? SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT
                                              : 0;
      format_.SubFormat = {0x00000001, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71}};
    }
    return create_source();
  }

  int32_t write(const void* samples, int32_t sample_count, int32_t bits_per_sample) {
    const auto bytes_per_sample = bits_per_sample / 8;
    if (bits_per_sample != format_.Format.wBitsPerSample || samples == nullptr || sample_count < 0 ||
        sample_count % format_.Format.nChannels != 0 ||
        static_cast<uint32_t>(sample_count) > XAUDIO2_MAX_BUFFER_BYTES / bytes_per_sample) {
      return E_INVALIDARG;
    }
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    collect_buffers();
    if (buffers_.size() >= max_queued_buffers) {
      return 1;
    }
    if (sample_count == 0) {
      return S_OK;
    }

    const auto begin = static_cast<const uint8_t*>(samples);
    const auto byte_count = static_cast<UINT32>(sample_count) * bytes_per_sample;
    buffers_.emplace_back(begin, begin + byte_count);
    XAUDIO2_BUFFER buffer{};
    buffer.AudioBytes = byte_count;
    buffer.pAudioData = reinterpret_cast<const BYTE*>(buffers_.back().data());
    const auto result = source_->SubmitSourceBuffer(&buffer);
    if (FAILED(result)) {
      buffers_.pop_back();
    }
    return result;
  }

  HRESULT flush() {
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }

    // Stop/FlushSourceBuffers complete asynchronously. DestroyVoice waits until
    // the render thread has released the source, so its PCM can be freed safely.
    // The engine/mastering endpoint remain open; recreate only the source voice.
    destroy_source();
    return create_source();
  }

  HRESULT set_volume(float volume) {
    if (!std::isfinite(volume)) {
      return E_INVALIDARG;
    }
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    const auto clamped = std::clamp(volume, 0.0f, 1.0f);
    const auto result = source_->SetVolume(clamped, XAUDIO2_COMMIT_NOW);
    if (SUCCEEDED(result)) {
      volume_ = clamped;
    }
    return result;
  }

  HRESULT pause() {
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    const auto result = source_->Stop(0, XAUDIO2_COMMIT_NOW);
    if (SUCCEEDED(result)) {
      paused_ = true;
    }
    return result;
  }

  HRESULT resume() {
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    const auto result = source_->Start(0, XAUDIO2_COMMIT_NOW);
    if (SUCCEEDED(result)) {
      paused_ = false;
    }
    return result;
  }

  int64_t collect_done_samples() {
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    const auto state = collect_buffers();
    const auto frames = state.SamplesPlayed - last_collected_frames_;
    last_collected_frames_ = state.SamplesPlayed;
    const auto maximum = static_cast<UINT64>(std::numeric_limits<int64_t>::max()) / format_.Format.nChannels;
    return static_cast<int64_t>(std::min(frames, maximum) * format_.Format.nChannels);
  }

  int32_t is_idle() {
    const auto failure = ready();
    if (FAILED(failure)) {
      return failure;
    }
    return collect_buffers().BuffersQueued == 0 ? 1 : 0;
  }

 private:
  AudioErrors errors_;
  CO_MTA_USAGE_COOKIE mta_cookie_ = nullptr;
  IXAudio2* engine_ = nullptr;
  IXAudio2MasteringVoice* mastering_ = nullptr;
  IXAudio2SourceVoice* source_ = nullptr;
  WAVEFORMATEXTENSIBLE format_{};
  std::deque<std::vector<uint8_t>> buffers_;
  UINT64 last_collected_frames_ = 0;
  bool callbacks_registered_ = false;
  bool paused_ = false;
  float volume_ = 1.0f;

  HRESULT ready() const {
    const auto failure = errors_.failure();
    return FAILED(failure) ? failure : source_ != nullptr ? S_OK : E_UNEXPECTED;
  }

  HRESULT create_source() {
    auto result = engine_->CreateSourceVoice(&source_, &format_.Format, 0, XAUDIO2_DEFAULT_FREQ_RATIO, &errors_);
    if (FAILED(result)) {
      return result;
    }
    result = source_->SetVolume(volume_, XAUDIO2_COMMIT_NOW);
    if (SUCCEEDED(result) && !paused_) {
      result = source_->Start(0, XAUDIO2_COMMIT_NOW);
    }
    if (FAILED(result)) {
      destroy_source();
    }
    return result;
  }

  void destroy_source() {
    if (source_ != nullptr) {
      source_->DestroyVoice();
      source_ = nullptr;
    }
    buffers_.clear();
    last_collected_frames_ = 0;
  }

  XAUDIO2_VOICE_STATE collect_buffers() {
    XAUDIO2_VOICE_STATE state{};
    source_->GetState(&state);
    // This worker is the only submitter and normal playback consumes buffers in
    // order. A smaller native count therefore retires precisely this prefix.
    while (buffers_.size() > state.BuffersQueued) {
      buffers_.pop_front();
    }
    return state;
  }
};

template <typename Action> int32_t invoke(void* output, Action&& action) noexcept {
  if (output == nullptr) {
    return E_INVALIDARG;
  }
  try {
    return action(*static_cast<XAudioOutput*>(output));
  } catch (const std::bad_alloc&) {
    return E_OUTOFMEMORY;
  } catch (...) {
    return E_FAIL;
  }
}

} // namespace

void* phonolite_xaudio_open(int32_t sample_rate, int32_t channels, int32_t device_id) {
  return phonolite_xaudio_open_format(sample_rate, channels, device_id, 16, 16);
}

void* phonolite_xaudio_open_format(int32_t sample_rate, int32_t channels, int32_t device_id, int32_t bits_per_sample,
                                   int32_t valid_bits_per_sample) {
  try {
    auto output = std::make_unique<XAudioOutput>();
    return SUCCEEDED(output->initialize(sample_rate, channels, device_id, bits_per_sample, valid_bits_per_sample))
               ? output.release()
               : nullptr;
  } catch (...) {
    return nullptr;
  }
}

void phonolite_xaudio_close(void* output) {
  delete static_cast<XAudioOutput*>(output);
}

int32_t phonolite_xaudio_write(void* output, const int16_t* samples, int32_t sample_count) {
  return invoke(output, [samples, sample_count](auto& player) { return player.write(samples, sample_count, 16); });
}

int32_t phonolite_xaudio_write32(void* output, const int32_t* samples, int32_t sample_count) {
  return invoke(output, [samples, sample_count](auto& player) { return player.write(samples, sample_count, 32); });
}

int32_t phonolite_xaudio_flush(void* output) {
  return invoke(output, [](auto& player) { return player.flush(); });
}

int32_t phonolite_xaudio_set_volume(void* output, float volume) {
  return invoke(output, [volume](auto& player) { return player.set_volume(volume); });
}

int32_t phonolite_xaudio_pause(void* output) {
  return invoke(output, [](auto& player) { return player.pause(); });
}

int32_t phonolite_xaudio_resume(void* output) {
  return invoke(output, [](auto& player) { return player.resume(); });
}

int64_t phonolite_xaudio_collect_done_samples(void* output) {
  return output == nullptr ? static_cast<int64_t>(E_INVALIDARG)
                           : static_cast<XAudioOutput*>(output)->collect_done_samples();
}

int32_t phonolite_xaudio_is_idle(void* output) {
  return invoke(output, [](auto& player) { return player.is_idle(); });
}
