import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Records accessibility graph updates without labels, values or other UI text.
/// The update limit applies across every accessibility session in this process.
class AccessibilityUpdateTrace {
  final void Function(String) write;
  final int maxUpdates;
  final String _launch = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  int _generation = 0;
  int _batch = 0;
  int _updates = 0;

  AccessibilityUpdateTrace({required this.write, this.maxUpdates = 128}) : assert(maxUpdates > 0);

  String get _session => '$_launch:$_generation';

  /// Starts a new tree session without renewing the process-wide capture limit.
  void reset() {
    _generation++;
    _batch = 0;
  }

  ui.SemanticsUpdateBuilder wrap(ui.SemanticsUpdateBuilder builder) {
    if (_updates >= maxUpdates) {
      return builder;
    }

    final session = _session;

    return _TracingSemanticsUpdateBuilder(builder, (nodes) => _record(session, nodes));
  }

  void _record(String session, List<Map<String, Object?>> nodes) {
    if (session != _session || _updates >= maxUpdates) {
      return;
    }

    _batch++;
    _updates++;

    write(
      'Windows accessibility update ${jsonEncode({'session': session, 'batch': _batch, 'nodes': nodes, 'last': _updates == maxUpdates})}',
    );
  }
}

class _TracingSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  final ui.SemanticsUpdateBuilder _builder;
  final void Function(List<Map<String, Object?>>) _record;
  final List<Map<String, Object?>> _nodes = [];

  _TracingSemanticsUpdateBuilder(this._builder, this._record);

  // Flutter evolves updateNode's named metadata between SDK versions. Keep the
  // forwarding boundary here so all original arguments reach the native builder
  // unchanged, including metadata this structural recorder does not inspect.
  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #updateNode) {
      return super.noSuchMethod(invocation);
    }

    final arguments = invocation.namedArguments;
    final node = <String, Object?>{
      'id': arguments[#id] as int,
      'children': (arguments[#childrenInTraversalOrder] as Int32List).toList(growable: false),
      'hitTestChildren': (arguments[#childrenInHitTestOrder] as Int32List).toList(growable: false),
      'traversalParent': arguments[#traversalParent] as int?,
    };

    Function.apply(_builder.updateNode, const [], arguments);
    _nodes.add(node);

    return null;
  }

  @override
  void updateCustomAction({required int id, String? label, String? hint, int overrideId = -1}) =>
      _builder.updateCustomAction(id: id, label: label, hint: hint, overrideId: overrideId);

  @override
  ui.SemanticsUpdate build() {
    final update = _builder.build();

    _record(_nodes);

    return update;
  }
}
