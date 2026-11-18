import 'package:phonolite_app/data/models/auth/account_revisions.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';

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
