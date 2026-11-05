/// The pages opened lately, which Go to offers first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// The ids of the pages opened lately, the latest first, remembered between
/// sessions.
class RecentPages extends PreferenceNotifier<List<String>> {
  static const int _kept = 30;

  @override
  String get key => 'recent.pages';

  @override
  List<String> decode(Object? saved) => <String>[
    if (saved case final List<Object?> ids) ...ids.whereType<String>(),
  ];

  @override
  Object? encode(List<String> ids) => ids;

  /// Puts [pageId] first.
  void visit(String pageId) {
    if (state.firstOrNull == pageId) return;
    save(
      List<String>.unmodifiable(<String>[
        pageId,
        ...state.where((id) => id != pageId).take(_kept - 1),
      ]),
    );
  }
}

final recentPagesProvider = NotifierProvider<RecentPages, List<String>>(
  RecentPages.new,
);
