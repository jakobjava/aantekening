/// The application's visual language.
library;

import 'package:flutter/material.dart';

/// Builds the light and dark themes.
///
/// The interface is deliberately quiet: notes carry the colour and structure,
/// so the surfaces around them stay near-neutral, dividers do the separating
/// instead of boxes and shadows, and the accent appears only on selection and
/// focus. Density is tightened because the navigation panes are lists that
/// benefit from showing more rows at once.
abstract final class AppTheme {
  /// Accent colour, used for selection, focus and the active tool.
  static const Color seed = Color(0xFF3B6EA5);

  /// Width of the notebook and page-list panes.
  static const double libraryPaneWidth = 248;
  static const double pageListPaneWidth = 268;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        horizontalTitleGap: 8,
        minLeadingWidth: 20,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }

  /// The colour of a navigation pane, one step off the page surface so the
  /// canvas reads as the focus of the window.
  static Color paneColor(ColorScheme scheme) => scheme.surfaceContainerLow;
}
