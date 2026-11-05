/// Defensive readers for decoded JSON.
///
/// Page documents are a user-facing, hand-editable file format, so every read
/// tolerates a missing or wrongly-typed field rather than throwing. Structural
/// problems that cannot be recovered from are reported by the caller as a
/// [PageFormatException] instead.
library;

import '../document/elements.dart' show PageFormatException;

/// Reads [key] as a [String], falling back to [fallback].
String readString(
  Map<String, Object?> json,
  String key, [
  String fallback = '',
]) {
  final value = json[key];
  return value is String ? value : fallback;
}

/// Reads [key] as a nullable [String].
String? readStringOrNull(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

/// Reads [key] as a [double], accepting any JSON number but one too large
/// for a double, read as infinity, which could not be written again.
double readDouble(
  Map<String, Object?> json,
  String key, [
  double fallback = 0,
]) => _finite(json[key]) ?? fallback;

/// Reads [key] as a nullable [double], as [readDouble] does.
double? readDoubleOrNull(Map<String, Object?> json, String key) =>
    _finite(json[key]);

/// [value] as a double, if it is a number that is not infinite.
double? _finite(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

/// Reads [key] as an [int], accepting any JSON number.
int readInt(Map<String, Object?> json, String key, [int fallback = 0]) {
  final value = json[key];
  return value is num ? value.toInt() : fallback;
}

/// Reads [key] as a nullable [int].
int? readIntOrNull(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is num ? value.toInt() : null;
}

/// Reads [key] as a [bool].
bool readBool(Map<String, Object?> json, String key, [bool fallback = false]) {
  final value = json[key];
  return value is bool ? value : fallback;
}

/// Reads [key] as a nested JSON object, or an empty map.
Map<String, Object?> readObject(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map
      ? value.cast<String, Object?>()
      : const <String, Object?>{};
}

/// Reads [key] as a nullable nested JSON object.
Map<String, Object?>? readObjectOrNull(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map ? value.cast<String, Object?>() : null;
}

/// Reads [key] as a list of JSON objects, skipping entries of the wrong shape.
List<Map<String, Object?>> readObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List) return const <Map<String, Object?>>[];
  final out = <Map<String, Object?>>[];
  for (final entry in value) {
    if (entry is Map) out.add(entry.cast<String, Object?>());
  }
  return out;
}

/// Reads [key] as a list of doubles, skipping non-numeric entries. A number
/// too large for a double is the largest there is, keeping its place among
/// the rest.
List<double> readDoubleList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) return const <double>[];
  final out = <double>[];
  for (final entry in value) {
    if (entry is num) {
      out.add(entry.toDouble().clamp(-double.maxFinite, double.maxFinite));
    }
  }
  return out;
}

/// Reads [key] as a list of strings, skipping non-string entries.
List<String> readStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) return const <String>[];
  return <String>[
    for (final entry in value)
      if (entry is String) entry,
  ];
}

/// Resolves [key] against an enum's [values] by name, falling back to
/// [fallback] for unknown or missing values so that a document written by a
/// newer version of the app still opens.
T readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
  T fallback,
) {
  final name = json[key];
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
