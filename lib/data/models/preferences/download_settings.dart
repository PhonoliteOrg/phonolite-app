import 'package:phonolite_app/data/models/downloads/download_quality.dart';

/// Download preferences belong to this installation, independently of servers.
class DownloadSettings {
  final DownloadQuality quality;

  const DownloadSettings({this.quality = DownloadQuality.original});

  factory DownloadSettings.fromJson(Map<String, dynamic> value) =>
      DownloadSettings(quality: DownloadQuality.fromWireValue(value['quality']));

  DownloadSettings copyWith({DownloadQuality? quality}) => DownloadSettings(quality: quality ?? this.quality);

  Map<String, dynamic> toJson() => {'quality': quality.wireValue};

  @override
  bool operator ==(Object other) => identical(this, other) || other is DownloadSettings && quality == other.quality;

  @override
  int get hashCode => quality.hashCode;
}
