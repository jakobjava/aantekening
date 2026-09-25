import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/editor/trackpad.dart';
import 'src/input_trace.dart';

void main() {
  AantekeningBinding.ensureInitialized();
  installInputTrace();
  registerFontLicence();
  runApp(const ProviderScope(child: AantekeningApp()));
}
