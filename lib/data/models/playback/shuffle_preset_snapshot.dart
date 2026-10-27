import 'package:flutter/foundation.dart' show immutable;

import 'package:phonolite_app/data/models/playback/shuffle_preset.dart';

@immutable
class ShufflePresetSnapshot {
  final int revision;
  final List<ShufflePreset> items;

  ShufflePresetSnapshot({required this.revision, required List<ShufflePreset> items})
    : items = List.unmodifiable(items);

  static ShufflePresetSnapshot fromJson(Map<String, dynamic> json) => ShufflePresetSnapshot(
    revision: (json['revision'] as num).toInt(),
    items: (json['items'] as List)
        .map((item) => ShufflePreset.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {'revision': revision, 'items': items.map((item) => item.toJson()).toList()};
}
