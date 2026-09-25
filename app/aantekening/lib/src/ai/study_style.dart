/// How a study set's page begins, the same for every kind.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';

import '../look/controls.dart';
import '../look/tones.dart';

/// The head of a study set's page: what kind it is, what it is about, and
/// what can be done with it.
class StudyHeader extends StatelessWidget {
  const StudyHeader({
    required this.kind,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    super.key,
  });

  final StudyKind kind;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SmallCaps(kind.label, color: tones.emphasis),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (subtitle case final subtitle?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: tones.muted),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
