import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:phonolite_app/ui/shared/design_system/controls/uri_text_input_formatter.dart';

void main() {
  const formatter = UriTextInputFormatter();

  for (final address in [
    '',
    '192.168.1.20',
    '192.168.1.20:3000',
    'localhost',
    'my-server.local',
    'https://music.test:8443/api',
    '[2001:db8::1]',
    'https://[::ffff:192.0.2.1]:8443/api',
    'https://xn--bcher-kva.test/%E2%9C%93',
    r"https://music.test/a-z_A.Z~!$&'()*+,;=:@/?q=a%20b#part",
  ]) {
    test('accepts URI characters in $address', () {
      final value = TextEditingValue(
        text: address,
        selection: TextSelection.collapsed(offset: address.length),
      );

      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), same(value));
    });
  }

  for (final character in [
    ' ',
    '\t',
    '\n',
    '\r',
    '\u0000',
    '\u007f',
    '"',
    '<',
    '>',
    '\\',
    '^',
    '`',
    '{',
    '|',
    '}',
    '😀',
    '‘',
    '—',
  ]) {
    test('rejects an edit containing ${character.codeUnits} without moving the caret', () {
      const previous = TextEditingValue(text: 'music.test', selection: TextSelection.collapsed(offset: 3));
      final next = TextEditingValue(text: 'mus${character}ic.test');

      expect(formatter.formatEditUpdate(previous, next), same(previous));
    });
  }

  test('rejects an entire invalid paste instead of changing its hostname', () {
    const pasted = TextEditingValue(text: 'https://my server.test:8443');

    expect(formatter.formatEditUpdate(TextEditingValue.empty, pasted), TextEditingValue.empty);
  });

  test('allows partial schemes, IPv6 and percent escapes during editing', () {
    for (final value in [
      'h',
      'http:',
      'http:/',
      'https://',
      '[',
      '[2001:',
      '[2001:db8::',
      'music.test/%',
      'music.test/%2',
    ]) {
      final next = TextEditingValue(text: value);

      expect(formatter.formatEditUpdate(TextEditingValue.empty, next), same(next));
    }
  });

  test('valid edits retain selection and keyboard composition', () {
    const next = TextEditingValue(
      text: 'music.test',
      selection: TextSelection(baseOffset: 2, extentOffset: 5),
      composing: TextRange(start: 0, end: 5),
    );

    expect(formatter.formatEditUpdate(TextEditingValue.empty, next), same(next));
  });
}
