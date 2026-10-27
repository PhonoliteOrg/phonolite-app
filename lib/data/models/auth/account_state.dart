import 'dart:math';

import 'package:phonolite_app/data/models/server/revision_event.dart';

/// Independent clocks; each domain commits in its own owning database.
class AccountRevisions {
  final int collections;
  final int presets;
  final int statistics;
  final int playback;

  const AccountRevisions({
    required this.collections,
    required this.presets,
    required this.statistics,
    this.playback = 0,
  });

  factory AccountRevisions.fromJson(Map<String, dynamic> json) {
    int revision(String key) {
      final value = json[key];

      if (value is! int || value < 0) {
        throw FormatException('Invalid $key revision');
      }

      return value;
    }

    return AccountRevisions(
      collections: revision('collections'),
      presets: revision('presets'),
      statistics: revision('statistics'),
      playback: json.containsKey('playback') ? revision('playback') : 0,
    );
  }

  AccountRevisions merge(AccountRevisions other) => AccountRevisions(
    collections: max(collections, other.collections),
    presets: max(presets, other.presets),
    statistics: max(statistics, other.statistics),
    playback: max(playback, other.playback),
  );

  bool isAheadOf(AccountRevisions other) =>
      collections > other.collections ||
      presets > other.presets ||
      statistics > other.statistics ||
      playback > other.playback;

  bool isBehind(AccountRevisions other) =>
      collections < other.collections ||
      presets < other.presets ||
      statistics < other.statistics ||
      playback < other.playback;
}

class AccountState {
  final String userId;
  final String username;
  final String role;
  final AccountRevisions revisions;

  const AccountState({required this.userId, required this.username, required this.role, required this.revisions});

  factory AccountState.fromJson(Map<String, dynamic> json) => AccountState(
    userId: json['user_id'] as String,
    username: json['username'] as String,
    role: json['role'] as String,
    revisions: AccountRevisions.fromJson(Map<String, dynamic>.from(json['revisions'] as Map)),
  );

  static RevisionEvent<AccountRevisions>? eventFromJson(Map<String, dynamic> json) {
    final kind = switch (json['kind']) {
      'ready' => RevisionEventKind.ready,
      'account_changed' => RevisionEventKind.changed,
      'revision' => RevisionEventKind.revision,
      _ => null,
    };

    if (kind == null) {
      return null;
    }

    return RevisionEvent(
      kind: kind,
      revision: AccountRevisions.fromJson(Map<String, dynamic>.from(json['revisions'] as Map)),
    );
  }
}
