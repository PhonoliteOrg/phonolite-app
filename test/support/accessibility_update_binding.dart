import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Checks the serialized deltas that desktop accessibility bridges consume.
/// Widget tests normally discard these updates before native tree validation.
class AccessibilityUpdateBinding extends AutomatedTestWidgetsFlutterBinding {
  final Map<int, List<int>> _tree = {};

  void resetAccessibilityTree() => _tree.clear();

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _AccessibilityUpdateBuilder(applyAccessibilityUpdate);

  void applyAccessibilityUpdate(Map<int, List<int>> updates) {
    if (updates.isEmpty) {
      return;
    }

    final nextTree = {for (final entry in _tree.entries) entry.key: List<int>.of(entry.value)};
    final parentsBeforeUpdate = {
      for (final entry in nextTree.entries)
        for (final child in entry.value) child: entry.key,
    };
    final removals = <int, List<int>>{};

    for (final entry in updates.entries) {
      for (final child in entry.value) {
        final oldParent = parentsBeforeUpdate[child];

        if (oldParent != null && oldParent != entry.key) {
          removals.putIfAbsent(oldParent, () => List<int>.of(nextTree[oldParent]!)).remove(child);
        }
      }
    }

    // The desktop bridge deletes moved subtrees before applying the new node
    // data. A final-graph check alone can retain descendants native AXTree lost.
    _applyBatch(nextTree, removals, phase: 'remove moved nodes');
    _applyBatch(nextTree, updates, phase: 'apply node data');
    _tree
      ..clear()
      ..addAll(nextTree);
    final reachable = <int>{};
    final visiting = <int>{};
    final parents = <int, int>{};

    void visit(int id) {
      expect(visiting, isNot(contains(id)), reason: 'Accessibility cycle at node $id');

      if (!reachable.add(id)) {
        return;
      }

      expect(_tree, contains(id), reason: 'Referenced accessibility node $id has not been serialized');
      visiting.add(id);

      for (final child in _tree[id]!) {
        expect(parents, isNot(contains(child)), reason: 'Accessibility node $child has multiple parents');
        parents[child] = id;
        visit(child);
      }

      visiting.remove(id);
    }

    visit(0);

    for (final id in updates.keys) {
      expect(reachable, contains(id), reason: 'Serialized accessibility node $id is disconnected from the root');
    }

    _tree.removeWhere((id, _) => !reachable.contains(id));
  }

  void _applyBatch(Map<int, List<int>> tree, Map<int, List<int>> updates, {required String phase}) {
    final pending = <int>{};
    final ordered = <int>[];
    final visited = <int>{};
    final childIds = updates.values.expand((children) => children).toSet();

    void order(int id) {
      if (!updates.containsKey(id) || !visited.add(id)) {
        return;
      }

      ordered.add(id);

      for (final child in updates[id]!) {
        order(child);
      }
    }

    for (final id in updates.keys.where((id) => !childIds.contains(id))) {
      order(id);
    }

    expect(visited, containsAll(updates.keys), reason: 'Accessibility update contains a cycle during $phase');

    void removeSubtree(int id) {
      final children = tree.remove(id);

      pending.remove(id);

      for (final child in children ?? const <int>[]) {
        removeSubtree(child);
      }
    }

    for (final id in ordered) {
      if (tree.isEmpty && id == 0) {
        tree[0] = [];
      }

      expect(tree, contains(id), reason: 'Accessibility node $id is absent during $phase; updates=$updates');

      final previousChildren = tree[id]!;
      final nextChildren = updates[id]!;

      for (final child in previousChildren.where((child) => !nextChildren.contains(child))) {
        removeSubtree(child);
      }

      for (final child in nextChildren.where((child) => !previousChildren.contains(child))) {
        expect(tree, isNot(contains(child)), reason: 'Accessibility node $child was reparented without removal');
        tree[child] = [];
        pending.add(child);
      }

      tree[id] = List<int>.of(nextChildren);
      pending.remove(id);
    }

    expect(pending, isEmpty, reason: 'Nodes left pending by the update during $phase: $pending; updates=$updates');
  }
}

class _AccessibilityUpdateBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  final void Function(Map<int, List<int>>) _checkUpdate;
  final ui.SemanticsUpdateBuilder _builder = ui.SemanticsUpdateBuilder();
  final Map<int, List<int>> _updates = {};

  _AccessibilityUpdateBuilder(this._checkUpdate);

  // Observing invocations keeps this test adapter independent of unrelated
  // metadata parameters added to SemanticsUpdateBuilder across Flutter SDKs.
  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #updateNode) {
      return super.noSuchMethod(invocation);
    }

    final id = invocation.namedArguments[#id] as int;
    final children = invocation.namedArguments[#childrenInTraversalOrder] as Int32List;

    expect(_updates, isNot(contains(id)), reason: 'Accessibility node $id was serialized twice in one update');
    _updates[id] = children.toList(growable: false);

    return null;
  }

  @override
  void updateCustomAction({required int id, String? label, String? hint, int overrideId = -1}) =>
      _builder.updateCustomAction(id: id, label: label, hint: hint, overrideId: overrideId);

  @override
  ui.SemanticsUpdate build() {
    _checkUpdate(_updates);

    return _builder.build();
  }
}
