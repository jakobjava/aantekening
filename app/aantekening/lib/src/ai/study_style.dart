/// How each kind of study set looks, the same wherever it shows: its
/// colour, its icon, and the head of its page.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';

extension StudyLook on StudyKind {
  IconData get icon => switch (this) {
    StudyKind.summary => Icons.article_outlined,
    StudyKind.flashcards => Icons.style_outlined,
    StudyKind.quiz => Icons.quiz_outlined,
    StudyKind.terms => Icons.sell_outlined,
  };

  /// Its colour, lighter on a dark page.
  Color accent(ColorScheme scheme) {
    final color = switch (this) {
      StudyKind.summary => const Color(0xFF3B6FD4),
      StudyKind.flashcards => const Color(0xFFD9822B),
      StudyKind.quiz => const Color(0xFF16A085),
      StudyKind.terms => const Color(0xFF8E5BD8),
    };
    return scheme.brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.3)!
        : color;
  }
}

/// [kind]'s icon on a tint of its colour.
class StudyBadge extends StatelessWidget {
  const StudyBadge(this.kind, {this.size = 36, super.key});

  final StudyKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = kind.accent(Theme.of(context).colorScheme);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(kind.icon, size: size * 0.55, color: color),
    );
  }
}

/// The head of a study set's page: what it is, what it is about, and what
/// can be done with it.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
      child: Row(
        children: <Widget>[
          StudyBadge(kind, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
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

/// A label in small capitals, spaced out, over a part of a page.
class SmallCaps extends StatelessWidget {
  const SmallCaps(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w700,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
