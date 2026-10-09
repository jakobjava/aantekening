import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/editor/trackpad.dart';
import 'src/input_trace.dart';

void main() {
  AantekeningBinding.ensureInitialized();
  installInputTrace();
  listenToTouchpadFingers();
  registerFontLicence();
  runApp(
    ProviderScope(
      // What fails is said at once, where it shows, for the person to try
      // again: never tried again unseen, behind a wheel turning for half a
      // minute.
      retry: (_, _) => null,
      child: const AantekeningApp(),
    ),
  );
}
