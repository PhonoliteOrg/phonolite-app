/// Shared decoding rules for values that tolerate older server schemas.
///
/// Models retain field names, required casts and subject-specific defaults.
/// These helpers own only the conversion rules explicitly shared by them.
abstract final class JsonValues {
  static String? nonEmptyString(Object? value) {
    final text = value?.toString().trim();

    return text == null || text.isEmpty ? null : text;
  }

  static List<String> strings(Object? value) =>
      value is List ? value.map((item) => item.toString()).toList() : const [];

  static int? optionalInteger(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim());
    }

    return null;
  }

  static int firstInteger(Map<String, dynamic> value, Iterable<String> keys) {
    for (final key in keys) {
      final parsed = optionalInteger(value[key]);
      if (parsed != null) {
        return parsed;
      }
    }

    return 0;
  }

  /// Download API dates accept milliseconds or ISO text. Missing dates use
  /// the receipt time; malformed nonempty dates retain the legacy epoch fallback.
  static DateTime downloadDate(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    final text = value?.toString();

    if (text == null || text.isEmpty) {
      return DateTime.now();
    }

    return DateTime.tryParse(text) ?? DateTime.fromMillisecondsSinceEpoch(int.tryParse(text) ?? 0);
  }
}
