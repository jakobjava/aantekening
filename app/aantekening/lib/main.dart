import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/input_trace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  installInputTrace();
  runApp(const ProviderScope(child: AantekeningApp()));
}
