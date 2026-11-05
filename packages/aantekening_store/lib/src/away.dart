/// Work too heavy for the isolate that asks for it.
library;

import 'dart:isolate';

export 'package:aantekening_core/aantekening_core.dart' show heavyBytes;

/// Runs [work] on [input] on an isolate of its own when [heavy], so that
/// the isolate asking — the window's, say — carries on meanwhile; here
/// otherwise, where starting an isolate would cost more than the work.
///
/// [work] is a function of its own, not a closure, and [input] something
/// that can be sent: a closure would take with it whatever it was made
/// among, a database perhaps, which cannot go to another isolate.
Future<R> away<I, R>(
  R Function(I input) work,
  I input, {
  required bool heavy,
}) async => heavy ? Isolate.run(() => work(input)) : work(input);
