import 'dart:typed_data';

import 'package:phonolite_opus/phonolite_opus.dart';

sealed class RawOpusEvent {}

class RawOpusStreamHeader extends RawOpusEvent {
  final Uint8List bytes;
  final RawOpusHeader header;

  RawOpusStreamHeader(this.bytes, this.header);
}

class RawOpusPacket extends RawOpusEvent {
  final Uint8List bytes;

  RawOpusPacket(this.bytes);
}

class RawOpusSeekMarker extends RawOpusEvent {
  final int seekId;

  RawOpusSeekMarker(this.seekId);
}

class RawOpusEnd extends RawOpusEvent {}
