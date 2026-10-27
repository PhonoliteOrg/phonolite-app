enum AccountCollectionEventKind { ready, collectionsChanged, revision }

/// An account-scoped invalidation, never a replayable collection delta.
class AccountCollectionEvent {
  final AccountCollectionEventKind kind;
  final int revision;

  const AccountCollectionEvent({required this.kind, required this.revision});

  static AccountCollectionEvent? tryFromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    final kind = switch (json['kind']) {
      'ready' => AccountCollectionEventKind.ready,
      'collections_changed' => AccountCollectionEventKind.collectionsChanged,
      'revision' => AccountCollectionEventKind.revision,
      _ => null,
    };

    if (kind == null || revision is! int || revision < 0) {
      return null;
    }

    return AccountCollectionEvent(kind: kind, revision: revision);
  }
}
