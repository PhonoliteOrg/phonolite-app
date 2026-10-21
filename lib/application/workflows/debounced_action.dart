import 'dart:async';

/// Owns one pending action; scheduling again replaces the previous action.
/// The feature chooses the delay and whether disposal must also flush work.
class DebouncedAction {
  Timer? _timer;

  void schedule(Duration delay, void Function() action) {
    cancel();

    void runPendingAction() {
      _timer = null;
      action();
    }

    _timer = Timer(delay, runPendingAction);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
