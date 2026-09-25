/// The pages opened lately, which Go to offers first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The ids of the pages opened lately, the latest first, remembered between
/// sessions.
class RecentPages extends Notifier<List<String>> {
  static const String _key = 'recent.pages';
  static const int _kept = 30;

  @override
  List<String> build() => <String>[
    if (ref.preference(_key) case final List<Object?> ids)
      ...ids.whereType<String>(),
  ];

  /// Puts [pageId] first.
  void visit(String pageId) {
    if (state.firstOrNull == pageId) return;
    state = List<String>.unmodifiable(<String>[
      pageId,
      ...state.where((id) => id != pageId).take(_kept - 1),
    ]);
    ref.savePreference(_key, state);
  }
}

final recentPagesProvider = NotifierProvider<RecentPages, List<String>>(
  RecentPages.new,
);
