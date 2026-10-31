// A protocol-free libpulse fixture. It never connects to an audio server.
#include <pulse/pulseaudio.h>

#include <algorithm>
#include <cstring>
#include <vector>

struct pa_mainloop {
  int dispatches = 0;
};
struct pa_context {
  pa_mainloop* loop;
};
struct pa_stream {
  pa_context* context;
};
struct pa_operation {
  pa_stream_success_cb_t callback = nullptr;
  void* data = nullptr;
  bool done = false;
  uint64_t started_ms = 0;
};

namespace {
pa_stream* current_stream = nullptr;
pa_operation* flushing = nullptr;
pa_operation* draining = nullptr;
std::vector<uint8_t> written;
pa_sample_spec format{};
pa_buffer_attr attributes{};
uint64_t latency = 0;
size_t writable = 1000000;
int context_flags = 0;
int stream_flags = 0;
int paused = 0;
int volume = 0;
int error_code = 0;
bool flush_success = true;
bool flush_ready = true;
bool drain_ready = false;
bool drain_success = true;
int handles = 0;
uint64_t elapsed_ms = 0;
int drain_requests = 0;
bool clocked_playback = false;
uint64_t played_bytes = 0;

size_t frame_size() {
  return format.channels * (format.format == PA_SAMPLE_S16LE ? 2 : 4);
}

uint64_t pending_bytes() {
  return written.size() - std::min<uint64_t>(written.size(), played_bytes);
}
} // namespace

extern "C" {
void pulse_test_reset() {
  written.clear();
  latency = 0;
  writable = 1000000;
  error_code = 0;
  flush_success = true;
  flush_ready = true;
  drain_ready = false;
  drain_success = true;
  elapsed_ms = 0;
  drain_requests = 0;
  clocked_playback = false;
  played_bytes = 0;
}
void pulse_test_advance_time(uint64_t milliseconds) {
  elapsed_ms += milliseconds;
  if (clocked_playback && !paused) {
    played_bytes = std::min<uint64_t>(written.size(), played_bytes + milliseconds * format.rate / 1000 * frame_size());
  }
}
void pulse_test_clocked_playback(int enabled) {
  clocked_playback = enabled != 0;
}
void pulse_test_latency(uint64_t value) {
  latency = value;
}
void pulse_test_writable(uint64_t value) {
  writable = value;
}
void pulse_test_error(int value) {
  error_code = value;
}
void pulse_test_flush_success(int value) {
  flush_success = value != 0;
}
void pulse_test_flush_ready(int value) {
  flush_ready = value != 0;
}
void pulse_test_drain_ready(int value) {
  drain_ready = value != 0;
}
void pulse_test_drain_success(int value) {
  drain_success = value != 0;
}
int pulse_test_value(int key) {
  switch (key) {
  case 0:
    return handles;
  case 1:
    return format.format;
  case 2:
    return format.rate;
  case 3:
    return format.channels;
  case 4:
    return context_flags;
  case 5:
    return stream_flags;
  case 6:
    return paused;
  case 7:
    return volume;
  case 8:
    return written.size();
  case 9:
    return attributes.maxlength;
  case 10:
    return attributes.prebuf;
  case 11:
    return draining != nullptr;
  case 12:
    return drain_requests;
  case 13:
    return played_bytes;
  default:
    return -1;
  }
}
int pulse_test_byte(int index) {
  return written.at(index);
}

pa_mainloop* pa_mainloop_new() {
  ++handles;
  return new pa_mainloop;
}
void pa_mainloop_free(pa_mainloop* loop) {
  --handles;
  delete loop;
}
pa_mainloop_api* pa_mainloop_get_api(pa_mainloop* loop) {
  return reinterpret_cast<pa_mainloop_api*>(loop);
}
int pa_mainloop_iterate(pa_mainloop* loop, int block, int*) {
  if (block)
    return -1;
  ++loop->dispatches;
  if (flushing && !flushing->done && flush_ready) {
    flushing->done = true;
    if (flush_success) {
      written.clear();
      played_bytes = 0;
    }
    flushing->callback(current_stream, flush_success, flushing->data);
  }
  if (draining && !draining->done && drain_ready && !paused && (!clocked_playback || pending_bytes() == 0)) {
    draining->done = true;
    draining->callback(current_stream, drain_success, draining->data);
  } else if (draining && !draining->done && elapsed_ms - draining->started_ms >= 30000) {
    draining->done = true;
    error_code = PA_ERR_TIMEOUT;
    draining->callback(current_stream, false, draining->data);
  }
  return 0;
}
pa_context* pa_context_new(pa_mainloop_api* api, const char*) {
  ++handles;
  return new pa_context{reinterpret_cast<pa_mainloop*>(api)};
}
int pa_context_connect(pa_context*, const char*, pa_context_flags_t flags, const pa_spawn_api*) {
  context_flags = flags;
  return 0;
}
pa_context_state_t pa_context_get_state(const pa_context* context) {
  if (error_code && error_code != PA_ERR_NODATA && error_code != PA_ERR_TIMEOUT)
    return PA_CONTEXT_FAILED;
  return context->loop->dispatches >= 2 ? PA_CONTEXT_READY : PA_CONTEXT_CONNECTING;
}
int pa_context_errno(const pa_context*) {
  return error_code;
}
const char* pa_strerror(int code) {
  return code == PA_ERR_TIMEOUT ? "Timeout" : "fixture server failure";
}
void pa_context_disconnect(pa_context*) {}
void pa_context_unref(pa_context* context) {
  --handles;
  delete context;
}
pa_stream* pa_stream_new(pa_context* context, const char*, const pa_sample_spec* spec, const pa_channel_map*) {
  ++handles;
  format = *spec;
  current_stream = new pa_stream{context};
  return current_stream;
}
int pa_stream_connect_playback(pa_stream*, const char*, const pa_buffer_attr* attr, pa_stream_flags_t flags,
                               const pa_cvolume*, pa_stream*) {
  attributes = *attr;
  stream_flags = flags;
  return 0;
}
pa_stream_state_t pa_stream_get_state(const pa_stream*) {
  return PA_STREAM_READY;
}
size_t pa_stream_writable_size(const pa_stream*) {
  if (clocked_playback) {
    return attributes.maxlength - std::min<uint64_t>(attributes.maxlength, pending_bytes());
  }
  return writable;
}
int pa_stream_write(pa_stream*, const void* data, size_t count, pa_free_cb_t free_callback, int64_t, pa_seek_mode_t) {
  if (free_callback || count > pa_stream_writable_size(current_stream))
    return -1;
  const auto* bytes = static_cast<const uint8_t*>(data);
  written.insert(written.end(), bytes, bytes + count);
  if (!clocked_playback)
    writable -= count;
  return 0;
}
int pa_stream_get_latency(pa_stream*, pa_usec_t* value, int* negative) {
  if (error_code)
    return -1;
  *value = latency + (clocked_playback ? pending_bytes() / frame_size() * 1000000 / format.rate : 0);
  *negative = 0;
  return 0;
}
pa_operation* pa_stream_flush(pa_stream*, pa_stream_success_cb_t callback, void* data) {
  ++handles;
  flushing = new pa_operation{callback, data, false};
  return flushing;
}
pa_operation* pa_stream_drain(pa_stream*, pa_stream_success_cb_t callback, void* data) {
  if (draining)
    return nullptr;
  ++handles;
  ++drain_requests;
  draining = new pa_operation{callback, data, false, elapsed_ms};
  return draining;
}
pa_operation* pa_stream_cork(pa_stream*, int value, pa_stream_success_cb_t, void*) {
  paused = value;
  ++handles;
  return new pa_operation{nullptr, nullptr, true};
}
uint32_t pa_stream_get_index(const pa_stream*) {
  return 5;
}
int pa_stream_disconnect(pa_stream*) {
  return 0;
}
void pa_stream_unref(pa_stream* stream) {
  --handles;
  delete stream;
  current_stream = nullptr;
}
pa_operation* pa_context_set_sink_input_volume(pa_context*, uint32_t, const pa_cvolume* value, pa_context_success_cb_t,
                                               void*) {
  volume = value->values[0];
  ++handles;
  return new pa_operation{nullptr, nullptr, true};
}
pa_operation_state_t pa_operation_get_state(const pa_operation* operation) {
  return operation->done ? PA_OPERATION_DONE : PA_OPERATION_RUNNING;
}
void pa_operation_cancel(pa_operation*) {}
void pa_operation_unref(pa_operation* operation) {
  if (operation == flushing)
    flushing = nullptr;
  if (operation == draining)
    draining = nullptr;
  --handles;
  delete operation;
}
}
