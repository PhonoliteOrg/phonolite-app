/// Invalidates asynchronous results without canceling the underlying operation.
///
/// Each independent request family owns a generation. Capture [current] when
/// starting work, or call [advance] when the new work supersedes older work.
/// Session, identity and lifecycle checks remain with the operation's owner.
class RequestGeneration {
  final bool Function()? _isActive;
  int _current = 0;

  RequestGeneration({bool Function()? isActive}) : _isActive = isActive;

  int get current => _current;

  int advance() => ++_current;

  bool isCurrent(int generation) => generation == _current && (_isActive?.call() ?? true);
}
