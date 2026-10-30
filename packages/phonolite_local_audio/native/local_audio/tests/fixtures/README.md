The short MP3 and FLAC tones are the existing decoder fixtures.

AAC (ADTS and MP4), ALAC, Vorbis, WAV and AIFF fixtures are copied from the
server's `crates/server/tests/fixtures/formats` directory. They are 48 kHz stereo
conversions of the same FLAC tone, generated once with FFmpeg 8.0 and checked
in. Tests decode these bytes through an in-memory QUIC-source descriptor;
they do not invoke FFmpeg, open network listeners or acquire audio devices.
