/// Typed accessors for sqlite3 result rows.
///
/// `Row` exposes values as `dynamic`; these helpers keep the casts in one
/// place so repositories stay readable under `strict-casts`.
library;

import 'package:sqlite3/sqlite3.dart';

String str(Row row, String column) => row[column] as String;

String? strOrNull(Row row, String column) => row[column] as String?;

int integer(Row row, String column) => (row[column] as num).toInt();

int? intOrNull(Row row, String column) {
  final value = row[column];
  return value == null ? null : (value as num).toInt();
}

double real(Row row, String column) => (row[column] as num).toDouble();
