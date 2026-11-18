import 'package:phonolite_app/infrastructure/audio/output/audio_pcm_output.dart';

/// An output whose writes wait for capacity in a bounded native queue.
/// Native queue capacity controls refill independently of audible playback
/// latency, which can exceed a software scheduling horizon. Flush and disposal
/// must cancel writes waiting for capacity.
abstract interface class BoundedAudioPcmOutput implements AudioPcmOutput {}
