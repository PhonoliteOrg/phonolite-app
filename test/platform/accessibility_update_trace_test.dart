import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/infrastructure/diagnostics/accessibility_update_trace.dart';

void main() {
  final binding = _TracingTestBinding();

  setUp(() {
    binding.configure();

    final semantics = binding.ensureSemantics();

    addTearDown(semantics.dispose);
  });

  testWidgets('real text and slider updates preserve every original metadata argument', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Semantics(
                label: 'private label',
                value: 'private value',
                hint: 'private hint',
                identifier: 'private identifier',
                child: const Text('private text'),
              ),
              Slider(value: 0.5, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(binding.sentNodes, isNotEmpty);
    expect(binding.receivedNodes, hasLength(binding.sentNodes.length));

    for (var i = 0; i < binding.sentNodes.length; i++) {
      final sent = binding.sentNodes[i];
      final received = binding.receivedNodes[i];

      expect(received.keys, unorderedEquals(sent.keys));

      for (final entry in sent.entries) {
        if (entry.value is double && (entry.value! as double).isNaN) {
          expect(received[entry.key], isNaN);
        } else {
          expect(received[entry.key], same(entry.value), reason: 'Argument ${entry.key} changed');
        }
      }
    }

    final traced = binding.logs.map(_decode).expand((batch) => batch['nodes']! as List).cast<Map>();

    expect(traced, isNotEmpty);
    for (final node in traced) {
      expect(node.keys, unorderedEquals(['id', 'children', 'hitTestChildren', 'traversalParent']));
    }
    expect(binding.logs.join(), isNot(contains('private')));
    expect(find.text('private text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom actions reach the native builder without recording their text', (tester) async {
    const action = CustomSemanticsAction(label: 'private action');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(customSemanticsActions: {action: () {}}, child: const Text('private action text')),
      ),
    );
    expect(binding.sentActions, isNotEmpty);
    expect(binding.receivedActions, binding.sentActions);
    expect(binding.receivedActions.single[#label], 'private action');
    expect(binding.logs.join(), isNot(contains('private')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tree sessions restart batch numbering while sharing one capture limit', (tester) async {
    binding.configure(maxUpdates: 3);

    Future<void> show(String label) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Semantics(label: label, child: const SizedBox(width: 20, height: 20)),
      ),
    );

    await show('first');
    expect(binding.logs, hasLength(1));
    final original = _decode(binding.logs.single);

    binding.trace.reset();
    await show('second');
    await show('third');
    await show('fourth');
    expect(binding.logs, hasLength(3));
    final second = _decode(binding.logs[1]);
    final last = _decode(binding.logs.last);

    expect(original['batch'], 1);
    expect(second['batch'], 1);
    expect(second['session'], isNot(original['session']));
    expect(last['session'], second['session']);
    expect(last['batch'], 2);
    expect(last['last'], isTrue);
    expect(binding.receivedNodes.any((arguments) => arguments[#label] == 'fourth'), isTrue);

    final nativeBuilder = ui.SemanticsUpdateBuilder();

    expect(binding.trace.wrap(nativeBuilder), same(nativeBuilder));
    nativeBuilder.build();
    expect(tester.takeException(), isNull);
  });

  test('a builder from a disabled session does not consume the next session budget', () {
    final logs = <String>[];
    final trace = AccessibilityUpdateTrace(write: logs.add, maxUpdates: 1);
    final stale = trace.wrap(ui.SemanticsUpdateBuilder());

    trace.reset();
    stale.build();
    expect(logs, isEmpty);
    trace.wrap(ui.SemanticsUpdateBuilder()).build();
    expect(logs, hasLength(1));
    expect(_decode(logs.single)['batch'], 1);
  });
}

Map<String, Object?> _decode(String log) {
  const prefix = 'Windows accessibility update ';

  expect(log, startsWith(prefix));

  return (jsonDecode(log.substring(prefix.length)) as Map).cast<String, Object?>();
}

class _TracingTestBinding extends AutomatedTestWidgetsFlutterBinding {
  final List<String> logs = [];
  final List<Map<Symbol, Object?>> sentNodes = [];
  final List<Map<Symbol, Object?>> receivedNodes = [];
  final List<Map<Symbol, Object?>> sentActions = [];
  final List<Map<Symbol, Object?>> receivedActions = [];
  late AccessibilityUpdateTrace trace;

  void configure({int maxUpdates = 128}) {
    logs.clear();
    sentNodes.clear();
    receivedNodes.clear();
    sentActions.clear();
    receivedActions.clear();
    trace = AccessibilityUpdateTrace(write: logs.add, maxUpdates: maxUpdates);
  }

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() {
    final nativeBuilder = _ObservingBuilder(super.createSemanticsUpdateBuilder(), receivedNodes, receivedActions);

    return _ObservingBuilder(trace.wrap(nativeBuilder), sentNodes, sentActions);
  }
}

class _ObservingBuilder implements ui.SemanticsUpdateBuilder {
  final ui.SemanticsUpdateBuilder _builder;
  final List<Map<Symbol, Object?>> _nodes;
  final List<Map<Symbol, Object?>> _actions;

  _ObservingBuilder(this._builder, this._nodes, this._actions);

  @override
  Object? noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #updateNode) {
      return super.noSuchMethod(invocation);
    }

    _nodes.add(Map<Symbol, Object?>.of(invocation.namedArguments));

    return Function.apply(_builder.updateNode, const [], invocation.namedArguments);
  }

  @override
  void updateCustomAction({required int id, String? label, String? hint, int overrideId = -1}) {
    _actions.add({#id: id, #label: label, #hint: hint, #overrideId: overrideId});
    _builder.updateCustomAction(id: id, label: label, hint: hint, overrideId: overrideId);
  }

  @override
  ui.SemanticsUpdate build() => _builder.build();
}
