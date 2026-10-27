/// Runs accepted actions in order without letting a failure block later work.
/// Each caller owns its action's errors; draining waits for actions added while
/// a previous action is still running. Accepted work is never canceled.
class SerialActionQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> add(Future<void> Function() action) {
    final result = _tail.then((_) => action());

    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    return result;
  }

  Future<void> drain() async {
    Future<void> pending;

    do {
      pending = _tail;
      await pending;
    } while (!identical(pending, _tail));
  }
}
