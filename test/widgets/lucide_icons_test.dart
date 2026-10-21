import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonolite_app/ui/shared/design_system/controls/lucide_checkbox.dart';
import 'package:phonolite_app/ui/features/search/widgets/search_filter_chips.dart';
import 'package:phonolite_app/ui/shared/design_system/icons/phonolite_icons.dart';

void main() {
  testWidgets('Lucide glyphs and license load from the bundled assets', (
    tester,
  ) async {
    final fontData = await rootBundle.load(
      'assets/icons/lucide/PhonoliteLucide.ttf',
    );
    final loader = FontLoader(PhonoliteIcons.fontFamily)
      ..addFont(Future.value(fontData));
    await loader.load();
    final license = await rootBundle.loadString('assets/icons/lucide/LICENSE');
    expect(license, contains('ISC License'));
    expect(license, contains('MIT License'));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Icon(PhonoliteIcons.play),
              Icon(PhonoliteIcons.disc3),
              Icon(PhonoliteIcons.heart),
              Icon(PhonoliteIcons.squareCheck),
            ],
          ),
        ),
      ),
    );
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      expect(icon.icon!.fontFamily, PhonoliteIcons.fontFamily);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lucide checkbox preserves keyboard, tap and checked semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var checked = false;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return LucideCheckbox(
                  value: checked,
                  autofocus: true,
                  onChanged: enabled
                      ? (value) => setState(() => checked = value!)
                      : null,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(PhonoliteIcons.square), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(checked, isTrue);
      expect(find.byIcon(PhonoliteIcons.squareCheck), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(Checkbox)),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(checked, isFalse);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(checked, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('search filter chips use Lucide checks and remain selectable', (
    tester,
  ) async {
    var selected = 'artist';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SearchFilterChips(
              activeFilter: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.showCheckmark, isFalse);
    }
    expect(find.byIcon(PhonoliteIcons.check), findsOneWidget);
    await tester.tap(find.text('ALBUM'));
    await tester.pumpAndSettle();
    expect(selected, 'album');
    expect(find.byIcon(PhonoliteIcons.check), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
