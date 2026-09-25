/// The application's visual language: one colour and its text, straight
/// edges, and at most one accent.
library;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'tones.dart';

/// Builds the themes from the [Appearance] chosen.
///
/// The interface is drawn in two colours, the base and the text, and the
/// shades mixed between them ([Tones]); an accent, if there is one, marks
/// what is picked, and nothing else has a colour of its own. Nothing is
/// rounded and nothing casts a shadow: lines separate things, and what
/// floats — a menu, a dialog — has an edge instead. Pressing something
/// shows at once rather than rippling out.
abstract final class AppTheme {
  /// The light theme of the appearance the app starts with.
  static ThemeData light() => build(const Appearance(), Brightness.light);

  /// The dark theme of the appearance the app starts with.
  static ThemeData dark() => build(const Appearance(), Brightness.dark);

  /// Nothing is rounded.
  static const OutlinedBorder square = RoundedRectangleBorder();

  static ThemeData build(Appearance appearance, Brightness brightness) {
    final tones = Tones.of(appearance, brightness);
    final scheme = _scheme(tones, brightness);
    final text = _textTheme(appearance.font, tones);
    final edge = BorderSide(color: tones.strongLine);
    final floating = RoundedRectangleBorder(side: edge);
    WidgetStateProperty<Color?> overlay({Color? pressed}) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return pressed ?? tones.pressed;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return tones.hover;
          }
          return null;
        });
    final buttonText = text.labelLarge;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12);
    const buttonSize = Size(0, 30);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<Object?>>[tones],
      fontFamily: appearance.font.family,
      textTheme: text,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      scaffoldBackgroundColor: tones.base,
      canvasColor: tones.base,
      cardColor: tones.base,
      dividerColor: tones.line,
      hoverColor: tones.hover,
      focusColor: tones.hover,
      highlightColor: tones.pressed,
      splashColor: Colors.transparent,
      disabledColor: tones.faint,
      shadowColor: Colors.transparent,
      iconTheme: IconThemeData(color: tones.text, size: 16),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tones.emphasis,
        selectionColor: tones.emphasis.withValues(alpha: 0.25),
        selectionHandleColor: tones.emphasis,
      ),
      dividerTheme: DividerThemeData(space: 1, thickness: 1, color: tones.line),
      listTileTheme: ListTileThemeData(
        dense: true,
        shape: square,
        horizontalTitleGap: 8,
        minLeadingWidth: 0,
        selectedColor: tones.text,
        selectedTileColor: tones.selection,
        textColor: tones.text,
        iconColor: tones.muted,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: false,
        hintStyle: TextStyle(color: tones.faint),
        labelStyle: TextStyle(color: tones.muted),
        floatingLabelStyle: TextStyle(color: tones.muted),
        helperStyle: TextStyle(color: tones.muted, fontSize: 11.5),
        helperMaxLines: 3,
        errorStyle: TextStyle(color: tones.text, fontSize: 11.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        // Only the shape: the edge takes its colour from the field's state —
        // strong at rest, the emphasis with the keyboard in it — and a field
        // that asks for no edge has none.
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
          minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
          textStyle: WidgetStatePropertyAll<TextStyle?>(buttonText),
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
          minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
          textStyle: WidgetStatePropertyAll<TextStyle?>(buttonText),
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? tones.line
                  : tones.strongLine,
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
          minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
          textStyle: WidgetStatePropertyAll<TextStyle?>(buttonText),
          elevation: const WidgetStatePropertyAll<double>(0),
          backgroundColor: _enabled(tones.emphasis, tones.line),
          foregroundColor: _enabled(tones.onEmphasis, tones.faint),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ||
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? tones.onEmphasis.withValues(alpha: 0.14)
                : null,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll<Size>(Size.square(26)),
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
          iconSize: const WidgetStatePropertyAll<double>(16),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          side: WidgetStatePropertyAll<BorderSide>(edge),
          textStyle: WidgetStatePropertyAll<TextStyle?>(buttonText),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? tones.selection : null,
          ),
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: square,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? tones.line
                : states.contains(WidgetState.selected)
                ? tones.emphasis
                : tones.strongLine,
          ),
        ),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? tones.emphasis : null,
        ),
        checkColor: WidgetStatePropertyAll<Color>(tones.onEmphasis),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        splashRadius: 0,
        visualDensity: VisualDensity.compact,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: Radius.zero,
        thickness: const WidgetStatePropertyAll<double>(6),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.dragged)
              ? tones.muted
              : states.contains(WidgetState.hovered)
              ? tones.faint
              : tones.strongLine,
        ),
        crossAxisMargin: 0,
        mainAxisMargin: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tones.emphasis,
        linearTrackColor: tones.line,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 2,
        // ignore: deprecated_member_use
        year2023: true,
        borderRadius: BorderRadius.zero,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(color: tones.text),
        textStyle: TextStyle(
          fontFamily: appearance.font.family,
          fontSize: 12,
          height: 1.35,
          color: tones.base,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tones.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: floating,
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.bodyMedium?.copyWith(
            color: states.contains(WidgetState.disabled)
                ? tones.faint
                : tones.text,
          ),
        ),
      ),
      menuTheme: MenuThemeData(style: _menuStyle(tones, floating)),
      menuBarTheme: MenuBarThemeData(style: _menuStyle(tones, floating)),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(square),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.bodyMedium),
          foregroundColor: _enabled(tones.text, tones.faint),
          iconColor: _enabled(tones.muted, tones.faint),
          iconSize: const WidgetStatePropertyAll<double>(14),
          overlayColor: overlay(),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: _menuStyle(tones, floating),
        textStyle: text.bodyMedium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tones.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: floating,
        insetPadding: const EdgeInsets.all(24),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        barrierColor: tones.text.withValues(
          alpha: brightness == Brightness.dark ? 0.12 : 0.18,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tones.text,
        contentTextStyle: text.bodyMedium?.copyWith(color: tones.base),
        actionTextColor: tones.base,
        shape: square,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        width: 480,
      ),
      cardTheme: CardThemeData(
        color: tones.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: tones.line)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(side: BorderSide(color: tones.line)),
        backgroundColor: tones.base,
        selectedColor: tones.selection,
        labelStyle: text.labelMedium,
        side: BorderSide(color: tones.line),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tones.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: floating,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: tones.base,
        elevation: 0,
        shape: square,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static MenuStyle _menuStyle(Tones tones, OutlinedBorder floating) =>
      MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(tones.base),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(floating),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(vertical: 4),
        ),
      );

  /// [enabled], or [disabled] while the control cannot be used.
  static WidgetStateProperty<Color> _enabled(Color enabled, Color disabled) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? disabled : enabled,
      );

  /// Material's colour roles, each given a tone, so any widget left to the
  /// theme's colours is drawn in them too.
  static ColorScheme _scheme(Tones tones, Brightness brightness) => ColorScheme(
    brightness: brightness,
    primary: tones.emphasis,
    onPrimary: tones.onEmphasis,
    primaryContainer: tones.selection,
    onPrimaryContainer: tones.text,
    secondary: tones.emphasis,
    onSecondary: tones.onEmphasis,
    secondaryContainer: tones.selection,
    onSecondaryContainer: tones.text,
    tertiary: tones.emphasis,
    onTertiary: tones.onEmphasis,
    tertiaryContainer: tones.selection,
    onTertiaryContainer: tones.text,
    // What went wrong is said in words; it is not given a colour of its own.
    error: tones.text,
    onError: tones.base,
    errorContainer: tones.hover,
    onErrorContainer: tones.text,
    surface: tones.base,
    onSurface: tones.text,
    onSurfaceVariant: tones.muted,
    surfaceDim: tones.pane,
    surfaceBright: tones.base,
    surfaceContainerLowest: tones.base,
    surfaceContainerLow: tones.mix(0.02),
    surfaceContainer: tones.pane,
    surfaceContainerHigh: tones.hover,
    surfaceContainerHighest: tones.pressed,
    surfaceTint: Colors.transparent,
    outline: tones.strongLine,
    outlineVariant: tones.line,
    shadow: Colors.transparent,
    scrim: tones.text.withValues(alpha: 0.2),
    inverseSurface: tones.text,
    onInverseSurface: tones.base,
    inversePrimary: tones.base,
  );

  /// Sizes for a desktop, where rows are read at arm's length and many of
  /// them show at once, in [font], coloured in [tones].
  static TextTheme _textTheme(InterfaceFont font, Tones tones) {
    TextStyle style(double size, FontWeight weight, {double height = 1.35}) =>
        TextStyle(
          fontFamily: font.family,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: 0,
          color: tones.text,
        );
    return TextTheme(
      displayLarge: style(40, FontWeight.w400, height: 1.15),
      displayMedium: style(32, FontWeight.w400, height: 1.15),
      displaySmall: style(26, FontWeight.w400, height: 1.2),
      headlineLarge: style(24, FontWeight.w600, height: 1.2),
      headlineMedium: style(21, FontWeight.w600, height: 1.25),
      headlineSmall: style(18, FontWeight.w600, height: 1.25),
      titleLarge: style(16, FontWeight.w600, height: 1.3),
      titleMedium: style(14, FontWeight.w600),
      titleSmall: style(13, FontWeight.w600),
      bodyLarge: style(14, FontWeight.w400, height: 1.45),
      bodyMedium: style(13, FontWeight.w400, height: 1.4),
      bodySmall: style(12, FontWeight.w400),
      labelLarge: style(13, FontWeight.w500),
      labelMedium: style(12, FontWeight.w500),
      labelSmall: style(11, FontWeight.w500),
    );
  }
}
