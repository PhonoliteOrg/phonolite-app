import 'package:flutter/services.dart';

/// Accepts RFC 3986 URI characters, including partial addresses while editing.
/// Component syntax and supported server URLs are validated when connecting.
class UriTextInputFormatter extends TextInputFormatter {
  // RFC 3986 sections 2.1–2.3: percent encoding, reserved and unreserved sets.
  // https://www.rfc-editor.org/rfc/rfc3986#section-2
  static final _invalidCharacters = RegExp(r'''[^A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]''');

  const UriTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Reject the edit intact: dropping a character from a pasted hostname could
    // silently change the server that the user intended to connect to.
    return _invalidCharacters.hasMatch(newValue.text) ? oldValue : newValue;
  }
}
