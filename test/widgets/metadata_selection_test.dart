import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/widgets/ui/dismissible_selection_area.dart';

void main() {
  for (final dismissLayer in [true, false]) {
    testWidgets(
      'metadata Copy reaches the platform with dismissLayer=$dismissLayer',
      (tester) async {
        String? selection;
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            if (call.method == 'Clipboard.hasStrings') {
              return {'value': copied?.isNotEmpty ?? false};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final app = MaterialApp(
          home: Scaffold(
            body: Center(
              child: DismissibleSelectionArea(
                onSelectionChanged: (content) => selection = content?.plainText,
                child: const Text('Selectable album metadata'),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          dismissLayer ? SelectionDismissLayer(child: app) : app,
        );
        final rect = tester.getRect(find.text('Selectable album metadata'));
        await tester.longPressAt(rect.topLeft + const Offset(4, 8));
        await tester.pumpAndSettle();
        final expected = selection;
        expect(expected?.trim(), isNotEmpty);
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(copied, expected);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
