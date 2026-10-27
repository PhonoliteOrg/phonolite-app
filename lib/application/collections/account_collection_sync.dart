import 'dart:math';

import 'package:phonolite_app/application/workflows/revision_snapshot_sync.dart';
import 'package:phonolite_app/data/models/collections/account_collection_event.dart';
import 'package:phonolite_app/data/models/collections/account_collection_snapshot.dart';
import 'package:phonolite_app/data/models/server/revision_event.dart';

/// Collection specialization of the shared revision reconciliation lifecycle.
class AccountCollectionSync extends RevisionSnapshotSync<AccountCollectionSnapshot, int> {
  AccountCollectionSync({
    required Stream<AccountCollectionEvent> Function() openStream,
    required super.fetchSnapshot,
    required super.applySnapshot,
    required super.isSessionCurrent,
    required super.onDiagnostic,
    super.onUnauthorized,
    super.onUnsupported,
    super.debounceDelay,
    super.retryDelay,
    super.reconnectDelay,
    super.maximumReconnectDelay,
    super.idleTimeout,
    super.reconnectJitter,
    super.random,
  }) : super(
         openStream: () => openStream().map(_revisionEvent),
         revisionOf: (snapshot) => snapshot.revision,
         merge: max,
         isAhead: (first, second) => first > second,
         isRollback: (first, second) => first < second,
       );

  static RevisionEvent<int> _revisionEvent(AccountCollectionEvent event) => RevisionEvent(
    kind: switch (event.kind) {
      AccountCollectionEventKind.ready => RevisionEventKind.ready,
      AccountCollectionEventKind.collectionsChanged => RevisionEventKind.changed,
      AccountCollectionEventKind.revision => RevisionEventKind.revision,
    },
    revision: event.revision,
  );
}
