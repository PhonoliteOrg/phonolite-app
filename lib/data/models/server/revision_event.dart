enum RevisionEventKind { ready, changed, revision }

/// A snapshot invalidation carrying a domain-owned scalar or vector revision.
class RevisionEvent<TRevision> {
  final RevisionEventKind kind;
  final TRevision revision;

  const RevisionEvent({required this.kind, required this.revision});
}
