import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reads back availability when a pop is attempted, including between frames.
///
/// Notify [canPopChanges] when availability changes so platform back handling
/// can also update before a gesture starts.
class LivePopScope<T> extends StatefulWidget {
  final bool Function() canPop;
  final Listenable? canPopChanges;
  final PopInvokedWithResultCallback<T>? onPopInvokedWithResult;
  final Widget child;

  const LivePopScope({
    super.key,
    required this.canPop,
    this.canPopChanges,
    this.onPopInvokedWithResult,
    required this.child,
  });

  @override
  State<LivePopScope<T>> createState() => _LivePopScopeState<T>();
}

class _LivePopScopeState<T> extends State<LivePopScope<T>> {
  ModalRoute<dynamic>? _route;
  late final _LivePopEntry<T> _entry;

  @override
  void initState() {
    super.initState();

    _entry = _LivePopEntry<T>(
      canPop: () => widget.canPop(),
      onPopInvokedWithResult: (didPop, result) => widget.onPopInvokedWithResult?.call(didPop, result),
    );

    widget.canPopChanges?.addListener(_entry.refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);

    if (identical(route, _route)) {
      return;
    }

    _route?.unregisterPopEntry(_entry);
    _route = route;
    _route?.registerPopEntry(_entry);
  }

  @override
  void didUpdateWidget(LivePopScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.canPopChanges, widget.canPopChanges)) {
      oldWidget.canPopChanges?.removeListener(_entry.refresh);
      widget.canPopChanges?.addListener(_entry.refresh);
    }

    _entry.refresh();
  }

  @override
  void dispose() {
    widget.canPopChanges?.removeListener(_entry.refresh);
    _route?.unregisterPopEntry(_entry);
    _entry.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _LivePopEntry<T> extends PopEntry<T> with ChangeNotifier implements ValueListenable<bool> {
  final bool Function() _canPop;
  final PopInvokedWithResultCallback<T> _onPopInvokedWithResult;
  late bool _lastCanPop;

  _LivePopEntry({required bool Function() canPop, required PopInvokedWithResultCallback<T> onPopInvokedWithResult})
    : _canPop = canPop,
      _onPopInvokedWithResult = onPopInvokedWithResult {
    _lastCanPop = value;
  }

  @override
  ValueListenable<bool> get canPopNotifier => this;

  @override
  bool get value => _canPop();

  @override
  void onPopInvokedWithResult(bool didPop, T? result) => _onPopInvokedWithResult(didPop, result);

  void refresh() {
    final canPop = value;

    if (_lastCanPop == canPop) {
      return;
    }

    _lastCanPop = canPop;

    notifyListeners();
  }
}
