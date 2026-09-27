/// Work too heavy for the isolate that asks for it.
library;

import 'dart:isolate';

/// How many bytes of a page make reading or writing it heavy: a page of
/// handwriting past this takes long enough to parse, write out or compress
/// that the window would stop while it did.
const int heavyBytes = 128 * 1024;

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
