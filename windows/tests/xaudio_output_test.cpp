// Exercise the real C ABI against fake native capabilities. No audio device,
// XAudio2 render engine, COM apartment or application is started by this test.
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#include <windows.h>

#include <mmsystem.h>

#include <mmddk.h>
#include <xaudio2.h>

#ifndef PHONOLITE_AUDIO_WINDOWS_EXPORTS
#define PHONOLITE_AUDIO_WINDOWS_EXPORTS
#endif
#include "../runner/infrastructure/audio/xaudio_output.h"

namespace xaudio_test {

void require(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAILED: " << description << '\n';
    std::exit(EXIT_FAILURE);
  }
}

template <typename Interface> class FakeVoice : public Interface {
 public:
  float volume = 1.0f;
  int gain_changes = 0;
  bool destroyed = false;
  HRESULT gain_result = S_OK;

  void STDMETHODCALLTYPE GetVoiceDetails(XAUDIO2_VOICE_DETAILS*) override {}
  HRESULT STDMETHODCALLTYPE SetOutputVoices(const XAUDIO2_VOICE_SENDS*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetEffectChain(const XAUDIO2_EFFECT_CHAIN*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE EnableEffect(UINT32, UINT32) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE DisableEffect(UINT32, UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetEffectState(UINT32, BOOL*) override {}
  HRESULT STDMETHODCALLTYPE SetEffectParameters(UINT32, const void*, UINT32, UINT32) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE GetEffectParameters(UINT32, void*, UINT32) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE SetFilterParameters(const XAUDIO2_FILTER_PARAMETERS*, UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetFilterParameters(XAUDIO2_FILTER_PARAMETERS*) override {}
  HRESULT STDMETHODCALLTYPE SetOutputFilterParameters(IXAudio2Voice*, const XAUDIO2_FILTER_PARAMETERS*,
                                                      UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetOutputFilterParameters(IXAudio2Voice*, XAUDIO2_FILTER_PARAMETERS*) override {}
  HRESULT STDMETHODCALLTYPE SetVolume(float value, UINT32 operation_set) override {
    require(!destroyed, "gain never accesses a destroyed source");
    require(operation_set == XAUDIO2_COMMIT_NOW, "gain is committed immediately");
    ++gain_changes;
    if (SUCCEEDED(gain_result))
      volume = value;
    return gain_result;
  }
  void STDMETHODCALLTYPE GetVolume(float* value) override {
    *value = volume;
  }
  HRESULT STDMETHODCALLTYPE SetChannelVolumes(UINT32, const float*, UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetChannelVolumes(UINT32, float*) override {}
  HRESULT STDMETHODCALLTYPE SetOutputMatrix(IXAudio2Voice*, UINT32, UINT32, const float*, UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetOutputMatrix(IXAudio2Voice*, UINT32, UINT32, float*) override {}
  void STDMETHODCALLTYPE DestroyVoice() override {
    destroyed = true;
  }
};

class FakeSource final : public FakeVoice<IXAudio2SourceVoice> {
 public:
  std::deque<XAUDIO2_BUFFER> queued;
  UINT64 played_frames = 0;
  UINT32 channels = 2;
  UINT32 bytes_per_sample = sizeof(int16_t);
  UINT32 sample_rate = 0;
  WORD valid_bits = 16;
  UINT32 head_frames = 0;
  int writes = 0;
  int starts = 0;
  int stops = 0;
  bool running = false;
  IXAudio2VoiceCallback* callbacks = nullptr;
  HRESULT submit_result = S_OK;

  HRESULT STDMETHODCALLTYPE Start(UINT32, UINT32) override {
    require(!destroyed, "start uses a live source");
    ++starts;
    running = true;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Stop(UINT32, UINT32) override {
    ++stops;
    running = false;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE SubmitSourceBuffer(const XAUDIO2_BUFFER* buffer, const XAUDIO2_BUFFER_WMA*) override {
    require(!destroyed, "write uses a live source");
    ++writes;
    if (SUCCEEDED(submit_result))
      queued.push_back(*buffer);
    return submit_result;
  }
  HRESULT STDMETHODCALLTYPE FlushSourceBuffers() override {
    require(false, "flush cannot free asynchronously borrowed buffers");
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE Discontinuity() override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE ExitLoop(UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetState(XAUDIO2_VOICE_STATE* state, UINT32) override {
    require(!destroyed, "state uses a live source");
    *state = {};
    state->BuffersQueued = static_cast<UINT32>(queued.size());
    state->SamplesPlayed = played_frames;
  }
  HRESULT STDMETHODCALLTYPE SetFrequencyRatio(float, UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetFrequencyRatio(float*) override {}
  HRESULT STDMETHODCALLTYPE SetSourceSampleRate(UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE DestroyVoice() override {
    require(!destroyed, "source is destroyed once");
    // XAudio2 may still read borrowed data until DestroyVoice returns.
    for (const auto& buffer : queued) {
      require(buffer.pAudioData != nullptr && buffer.AudioBytes != 0, "queued PCM survives until source destruction");
      volatile auto sample = *reinterpret_cast<const int16_t*>(buffer.pAudioData);
      (void)sample;
    }
    queued.clear();
    running = false;
    destroyed = true;
  }
  void consume(UINT32 frames) {
    require(running, "only a running source consumes PCM");
    while (frames > 0 && !queued.empty()) {
      const auto total = queued.front().AudioBytes / bytes_per_sample / channels;
      const auto consumed = std::min(frames, total - head_frames);
      played_frames += consumed;
      frames -= consumed;
      head_frames += consumed;
      if (head_frames == total) {
        queued.pop_front();
        head_frames = 0;
      }
    }
  }
  std::vector<int16_t> first_samples() const {
    require(!queued.empty(), "PCM is queued");
    const auto& first = queued.front();
    const auto* data = reinterpret_cast<const int16_t*>(first.pAudioData);
    return {data, data + first.AudioBytes / sizeof(int16_t)};
  }
};

class FakeMaster final : public FakeVoice<IXAudio2MasteringVoice> {
 public:
  HRESULT STDMETHODCALLTYPE GetChannelMask(DWORD*) override {
    return E_NOTIMPL;
  }
};

class FakeEngine final : public IXAudio2 {
 public:
  FakeMaster master;
  std::vector<std::unique_ptr<FakeSource>> sources;
  IXAudio2EngineCallback* callbacks = nullptr;
  std::wstring endpoint;
  int releases = 0;
  int unregisters = 0;
  HRESULT source_result = S_OK;
  HRESULT master_result = S_OK;

  FakeSource& source() {
    return *sources.back();
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID, void**) override {
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override {
    return 1;
  }
  ULONG STDMETHODCALLTYPE Release() override {
    ++releases;
    return 0;
  }
  HRESULT STDMETHODCALLTYPE RegisterForCallbacks(IXAudio2EngineCallback* callback) override {
    callbacks = callback;
    return S_OK;
  }
  void STDMETHODCALLTYPE UnregisterForCallbacks(IXAudio2EngineCallback* callback) override {
    require(callback == callbacks, "the registered engine callback is removed");
    ++unregisters;
    callbacks = nullptr;
  }
  HRESULT STDMETHODCALLTYPE CreateSourceVoice(IXAudio2SourceVoice** voice, const WAVEFORMATEX* format, UINT32, float,
                                              IXAudio2VoiceCallback* callback, const XAUDIO2_VOICE_SENDS*,
                                              const XAUDIO2_EFFECT_CHAIN*) override {
    if (FAILED(source_result))
      return source_result;
    auto source = std::make_unique<FakeSource>();
    source->channels = format->nChannels;
    source->bytes_per_sample = format->wBitsPerSample / 8;
    source->sample_rate = format->nSamplesPerSec;
    source->valid_bits = format->wFormatTag == WAVE_FORMAT_EXTENSIBLE
                             ? reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(format)->Samples.wValidBitsPerSample
                             : format->wBitsPerSample;
    source->callbacks = callback;
    *voice = source.get();
    sources.push_back(std::move(source));
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE CreateSubmixVoice(IXAudio2SubmixVoice**, UINT32, UINT32, UINT32, UINT32,
                                              const XAUDIO2_VOICE_SENDS*, const XAUDIO2_EFFECT_CHAIN*) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE CreateMasteringVoice(IXAudio2MasteringVoice** voice, UINT32, UINT32, UINT32, LPCWSTR device,
                                                 const XAUDIO2_EFFECT_CHAIN*, AUDIO_STREAM_CATEGORY category) override {
    endpoint = device == nullptr ? L"" : device;
    require(category == AudioCategory_Media, "output uses the media category");
    if (FAILED(master_result))
      return master_result;
    *voice = &master;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE StartEngine() override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE StopEngine() override {}
  HRESULT STDMETHODCALLTYPE CommitChanges(UINT32) override {
    return E_NOTIMPL;
  }
  void STDMETHODCALLTYPE GetPerformanceData(XAUDIO2_PERFORMANCE_DATA*) override {}
  void STDMETHODCALLTYPE SetDebugConfiguration(const XAUDIO2_DEBUG_CONFIGURATION*, void*) override {}
};

FakeEngine* engine = nullptr;
int mta_increments = 0;
int mta_decrements = 0;
int device_queries = 0;
bool endpoint_available = true;
HRESULT create_result = S_OK;

HRESULT fake_create(IXAudio2** result, UINT32, XAUDIO2_PROCESSOR) {
  if (FAILED(create_result))
    return create_result;
  *result = engine;
  return S_OK;
}
HRESULT fake_increment_mta(CO_MTA_USAGE_COOKIE* cookie) {
  ++mta_increments;
  *cookie = reinterpret_cast<CO_MTA_USAGE_COOKIE>(static_cast<UINT_PTR>(1));
  return S_OK;
}
HRESULT fake_decrement_mta(CO_MTA_USAGE_COOKIE) {
  ++mta_decrements;
  return S_OK;
}
UINT fake_num_devices() {
  return 2;
}
MMRESULT fake_wave_message(HWAVEOUT device, UINT message, DWORD_PTR first, DWORD_PTR second) {
  ++device_queries;
  require(reinterpret_cast<UINT_PTR>(device) == 1, "the exact selected WinMM index is queried");
  if (!endpoint_available)
    return MMSYSERR_NOTSUPPORTED;
  constexpr wchar_t endpoint[] = L"selected-endpoint";
  if (message == DRV_QUERYFUNCTIONINSTANCEIDSIZE) {
    *reinterpret_cast<ULONG*>(first) = sizeof(endpoint);
  } else {
    require(message == DRV_QUERYFUNCTIONINSTANCEID && second == sizeof(endpoint), "endpoint query uses its byte size");
    std::copy(std::begin(endpoint), std::end(endpoint), reinterpret_cast<wchar_t*>(first));
  }
  return MMSYSERR_NOERROR;
}

struct Fixture {
  FakeEngine audio;
  void* output = nullptr;
  explicit Fixture(int device_id = -1, int bits_per_sample = 16, int valid_bits_per_sample = 16,
                   int sample_rate = 48000) {
    engine = &audio;
    create_result = S_OK;
    endpoint_available = true;
    output = bits_per_sample == 16 ? phonolite_xaudio_open(sample_rate, 2, device_id)
                                  : phonolite_xaudio_open_format(sample_rate, 2, device_id, bits_per_sample,
                                                                 valid_bits_per_sample);
    require(output != nullptr, "valid output opens with fake capabilities");
  }
  ~Fixture() {
    phonolite_xaudio_close(output);
    require(audio.releases == 1 && audio.unregisters == 1, "engine resources retire once");
    require(audio.master.destroyed, "mastering voice retires");
    for (const auto& source : audio.sources)
      require(source->destroyed, "every source retires");
    engine = nullptr;
  }
};

} // namespace xaudio_test

// Replace only capability entry points; all queue, gain, error and lifetime
// behavior below is the production implementation compiled into this test.
#define XAudio2Create xaudio_test::fake_create
#define CoIncrementMTAUsage xaudio_test::fake_increment_mta
#define CoDecrementMTAUsage xaudio_test::fake_decrement_mta
#define waveOutGetNumDevs xaudio_test::fake_num_devices
#define waveOutMessage xaudio_test::fake_wave_message
#include "../runner/infrastructure/audio/xaudio_output.cpp"
#undef XAudio2Create
#undef CoIncrementMTAUsage
#undef CoDecrementMTAUsage
#undef waveOutGetNumDevs
#undef waveOutMessage

namespace xaudio_test {

void live_gain_changes_queued_audio_without_requeue() {
  Fixture fixture;
  auto& source = fixture.audio.source();
  std::vector<int16_t> samples{-32768, 32767, -2000, 2000};
  require(phonolite_xaudio_write(fixture.output, samples.data(), static_cast<int32_t>(samples.size())) == S_OK,
          "PCM is accepted");
  const auto* queued_data = source.queued.front().pAudioData;
  samples.assign(samples.size(), 0);
  require(source.first_samples() == std::vector<int16_t>({-32768, 32767, -2000, 2000}),
          "native queue owns an unscaled PCM copy");
  for (const auto level : {0.5f, 0.0f, 0.25f, 1.0f}) {
    require(phonolite_xaudio_set_volume(fixture.output, level) == S_OK && source.volume == level,
            "slider and mute update native source gain immediately");
    require(source.queued.front().pAudioData == queued_data && source.writes == 1 && source.starts == 1 &&
                source.stops == 0 && !source.destroyed,
            "gain does not rewrite, requeue or restart existing audio");
  }
  require(source.first_samples().front() == -32768, "muting retains PCM for unmute");
  require(fixture.audio.master.gain_changes == 0, "gain changes only the source voice");
  require(phonolite_xaudio_set_volume(fixture.output, 3.0f) == S_OK && source.volume == 1.0f, "gain clamps high");
  require(phonolite_xaudio_set_volume(fixture.output, -1.0f) == S_OK && source.volume == 0.0f, "gain clamps low");
  require(phonolite_xaudio_set_volume(fixture.output, std::numeric_limits<float>::quiet_NaN()) == E_INVALIDARG,
          "invalid gain is rejected");
}

void queue_bound_and_played_sample_accounting() {
  Fixture fixture;
  auto& source = fixture.audio.source();
  const std::vector<int16_t> samples{-100, 100, -200, 200};
  for (int i = 0; i < 5; ++i) {
    require(phonolite_xaudio_write(fixture.output, samples.data(), 4) == S_OK, "queue accepts bounded PCM");
  }
  require(phonolite_xaudio_write(fixture.output, samples.data(), 4) == 1 && source.writes == 5,
          "full queue rejects without submitting another buffer");
  require(phonolite_xaudio_set_volume(fixture.output, 0.0f) == S_OK && source.volume == 0.0f,
          "mute is immediate while the queue is full");
  source.consume(3);
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 6, "progress counts actual interleaved samples");
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 0, "progress is reported once");
  require(phonolite_xaudio_write(fixture.output, samples.data(), 4) == S_OK, "completed prefix frees queue space");
  source.consume(9);
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 18, "remaining progress includes partial buffers");
  require(phonolite_xaudio_is_idle(fixture.output) == 1, "fully consumed queue becomes idle");
}

void flush_preserves_gain_pause_and_discards_old_progress() {
  Fixture fixture;
  auto& first = fixture.audio.source();
  const std::vector<int16_t> samples{-100, 100, -200, 200};
  require(phonolite_xaudio_write(fixture.output, samples.data(), 4) == S_OK, "old PCM queues");
  first.consume(1);
  require(phonolite_xaudio_set_volume(fixture.output, 0.25f) == S_OK, "gain changes before flush");
  require(phonolite_xaudio_pause(fixture.output) == S_OK, "source pauses");
  require(phonolite_xaudio_flush(fixture.output) == S_OK && first.destroyed, "flush releases old borrowed PCM first");
  auto& second = fixture.audio.source();
  require(&second != &first && second.volume == 0.25f && !second.running && second.starts == 0,
          "fresh source preserves gain and pause state");
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 0 && phonolite_xaudio_is_idle(fixture.output) == 1,
          "flush does not count discarded audio");
  require(phonolite_xaudio_write(fixture.output, samples.data(), 4) == S_OK, "new PCM queues while paused");
  require(phonolite_xaudio_set_volume(fixture.output, 0.0f) == S_OK && second.volume == 0.0f && !second.running,
          "paused mute changes gain without resuming");
  require(phonolite_xaudio_resume(fixture.output) == S_OK && second.running, "resume starts the fresh source");
  second.consume(2);
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 4, "fresh source has independent counters");
}

void selected_device_and_failure_cleanup() {
  {
    const auto queries = device_queries;
    Fixture fixture(1);
    require(fixture.audio.endpoint == L"selected-endpoint" && device_queries == queries + 2,
            "selected WinMM device resolves to the exact XAudio2 endpoint");
  }
  FakeEngine audio;
  engine = &audio;
  endpoint_available = false;
  require(phonolite_xaudio_open(48000, 2, 1) == nullptr, "unresolvable explicit endpoint does not fall back");
  require(audio.releases == 1 && audio.unregisters == 1, "failed endpoint lookup releases engine");
  endpoint_available = true;
  create_result = E_FAIL;
  const auto decrements = mta_decrements;
  require(phonolite_xaudio_open(48000, 2, -1) == nullptr && mta_decrements == decrements + 1,
          "engine creation failure releases MTA usage");
  create_result = S_OK;
  engine = nullptr;
  require(phonolite_xaudio_open(0, 2, -1) == nullptr, "invalid format does not create an engine");
}

void render_errors_propagate_instead_of_stalling() {
  {
    Fixture fixture;
    fixture.audio.callbacks->OnCriticalError(XAUDIO2_E_DEVICE_INVALIDATED);
    const std::vector<int16_t> samples{-100, 100};
    require(phonolite_xaudio_write(fixture.output, samples.data(), 2) == XAUDIO2_E_DEVICE_INVALIDATED,
            "engine failure ends a pending producer wait");
    require(phonolite_xaudio_is_idle(fixture.output) == XAUDIO2_E_DEVICE_INVALIDATED &&
                phonolite_xaudio_collect_done_samples(fixture.output) == XAUDIO2_E_DEVICE_INVALIDATED,
            "progress and drain expose engine failure");
  }
  {
    Fixture fixture;
    fixture.audio.source().callbacks->OnVoiceError(nullptr, E_FAIL);
    require(phonolite_xaudio_set_volume(fixture.output, 0.0f) == E_FAIL, "source render failure is surfaced");
  }
  require(phonolite_xaudio_set_volume(nullptr, 0.0f) == E_INVALIDARG &&
              phonolite_xaudio_collect_done_samples(nullptr) == E_INVALIDARG,
          "null output operations fail safely");
  phonolite_xaudio_close(nullptr);
}

void original_pcm_preserves_source_rate_precision_and_progress() {
  Fixture fixture(-1, 32, 24, 192000);
  auto& source = fixture.audio.source();
  require(source.sample_rate == 192000 && source.bytes_per_sample == 4 && source.valid_bits == 24,
          "Original retains source sample rate and valid precision in a PCM32 container");
  const std::vector<int32_t> samples{std::numeric_limits<int32_t>::min(), 0x7fffff00, -256, 256};
  require(phonolite_xaudio_write32(fixture.output, samples.data(), 4) == S_OK, "Original PCM32 queues");
  const auto& buffer = source.queued.front();
  const auto* queued = reinterpret_cast<const int32_t*>(buffer.pAudioData);
  require(buffer.AudioBytes == 16 && std::equal(samples.begin(), samples.end(), queued),
          "Original preserves the low eight bits beyond PCM16 without modifying samples");
  const std::vector<int16_t> incompatible{-1, 1};
  require(phonolite_xaudio_write(fixture.output, incompatible.data(), 2) == E_INVALIDARG,
          "a PCM16 write cannot reinterpret PCM32 output data");
  source.consume(1);
  require(phonolite_xaudio_collect_done_samples(fixture.output) == 2,
          "PCM32 progress is counted in samples rather than bytes");
  require(phonolite_xaudio_flush(fixture.output) == S_OK, "Original seeking recreates the source");
  require(fixture.audio.source().sample_rate == 192000 && fixture.audio.source().valid_bits == 24,
          "seek retains original sample rate and precision");

  Fixture full_precision(-1, 32, 32, 96000);
  const std::vector<int32_t> exact{std::numeric_limits<int32_t>::max(), -1, 1, std::numeric_limits<int32_t>::min()};
  require(phonolite_xaudio_write32(full_precision.output, exact.data(), 4) == S_OK, "full PCM32 source queues");
  const auto* retained = reinterpret_cast<const int32_t*>(full_precision.audio.source().queued.front().pAudioData);
  require(std::equal(exact.begin(), exact.end(), retained), "every PCM32 source bit reaches the native queue");
}

} // namespace xaudio_test

int main() {
  xaudio_test::live_gain_changes_queued_audio_without_requeue();
  xaudio_test::queue_bound_and_played_sample_accounting();
  xaudio_test::flush_preserves_gain_pause_and_discards_old_progress();
  xaudio_test::selected_device_and_failure_cleanup();
  xaudio_test::render_errors_propagate_instead_of_stalling();
  xaudio_test::original_pcm_preserves_source_rate_precision_and_progress();
  xaudio_test::require(xaudio_test::mta_increments == xaudio_test::mta_decrements,
                       "MTA usage is balanced on all paths");
  std::cout << "XAudio2 native contracts passed (fake capabilities; no audio device opened).\n";
  return EXIT_SUCCESS;
}
