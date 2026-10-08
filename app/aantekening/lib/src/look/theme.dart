/// The application's visual language: one colour and its text, at most one
/// accent, soft corners, and glass over the page.
library;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'glass.dart';
import 'motion.dart';
import 'tones.dart';

/// Builds the themes from the [Appearance] chosen.
///
/// The interface is drawn in two colours, the base and the text, and the
/// shades mixed between them ([Tones]); an accent, if there is one, marks
/// what is picked, and nothing else has a colour of its own. Corners are
/// soft ([Corners]); what floats — a menu, a dialog — has a fine edge and
/// casts a soft shadow. Pressing something shows rather than rippling
/// out, and what changes colour does so as fast as the interface moves
/// ([Motion]).
abstract final class AppTheme {
  /// The light theme of the appearance the app starts with.
  static ThemeData light() => build(const Appearance(), Brightness.light);

  /// The dark theme of the appearance the app starts with.
  static ThemeData dark() => build(const Appearance(), Brightness.dark);

  /// What is pressed or typed in.
  static const OutlinedBorder rounded = RoundedRectangleBorder(
    borderRadius: Corners.controlRadius,
  );

  /// How deep what floats lies over the page, for its shadow.
  static const double _floatingElevation = 10;

  static ThemeData build(Appearance appearance, Brightness brightness) {
    final tones = Tones.of(appearance, brightness);
    final motion = Motion(appearance.motion);
    final changing = motion.of(Motion.quick);
    final scheme = _scheme(tones, brightness);
    final text = _textTheme(appearance.font, tones);
    final edge = BorderSide(color: tones.strongLine);
    final floating = RoundedRectangleBorder(
      borderRadius: Corners.panelRadius,
      side: BorderSide(color: tones.glassRim),
    );
    WidgetStateProperty<Color?> overlay({Color? pressed}) =>
        WidgetStateProperty.resolveWith((states) {
          // Clear, as what they lie on may be glass.
          if (states.contains(WidgetState.pressed)) {
            return pressed ?? tones.lift;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return tones.veil;
          }
          return null;
        });
    final buttonText = text.labelLarge;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 12);
    const buttonSize = Size(0, 30);
    // What every kind of button with words in it shares.
    final button = ButtonStyle(
      animationDuration: changing,
      shape: const WidgetStatePropertyAll<OutlinedBorder>(rounded),
      padding: const WidgetStatePropertyAll<EdgeInsets>(buttonPadding),
      minimumSize: const WidgetStatePropertyAll<Size>(buttonSize),
      textStyle: WidgetStatePropertyAll<TextStyle?>(buttonText),
      elevation: const WidgetStatePropertyAll<double>(0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<Object?>>[tones, motion],
      fontFamily: appearance.font.family,
      textTheme: text,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      splashFactory: NoSplash.splashFactory,
      scaffoldBackgroundColor: tones.base,
      canvasColor: tones.base,
      cardColor: tones.base,
      dividerColor: tones.line,
      hoverColor: tones.veil,
      focusColor: tones.veil,
      highlightColor: tones.lift,
      splashColor: Colors.transparent,
      disabledColor: tones.faint,
      shadowColor: tones.shadow,
      iconTheme: IconThemeData(color: tones.text, size: 16),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: tones.emphasis,
        selectionColor: tones.emphasis.withValues(alpha: 0.25),
        selectionHandleColor: tones.emphasis,
      ),
      dividerTheme: DividerThemeData(space: 1, thickness: 1, color: tones.line),
      listTileTheme: ListTileThemeData(
        dense: true,
        shape: rounded,
        horizontalTitleGap: 8,
        minLeadingWidth: 0,
        selectedColor: tones.text,
        selectedTileColor: tones.selection,
        textColor: tones.text,
        iconColor: tones.muted,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
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
        border: const OutlineInputBorder(borderRadius: Corners.controlRadius),
      ),
      textButtonTheme: TextButtonThemeData(
        style: button.copyWith(
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
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
        style: button.copyWith(
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
          animationDuration: changing,
          shape: const WidgetStatePropertyAll<OutlinedBorder>(rounded),
          padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
          minimumSize: const WidgetStatePropertyAll<Size>(Size.square(26)),
          foregroundColor: _enabled(tones.text, tones.faint),
          overlayColor: overlay(),
          iconSize: const WidgetStatePropertyAll<double>(16),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          animationDuration: changing,
          shape: const WidgetStatePropertyAll<OutlinedBorder>(rounded),
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
        shape: const RoundedRectangleBorder(borderRadius: Corners.smallRadius),
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
        radius: const Radius.circular(3),
        thickness: const WidgetStatePropertyAll<double>(6),
        // In the accent, where there is one, or the text's colour.
        thumbColor: WidgetStatePropertyAll<Color>(tones.emphasis),
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
        borderRadius: const BorderRadius.all(Radius.circular(1)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        // A little panel of its own, as the menus and dialogs are.
        decoration: BoxDecoration(
          color: tones.raised,
          border: Border.all(color: tones.glassRim),
          borderRadius: Corners.controlRadius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: tones.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: TextStyle(
          fontFamily: appearance.font.family,
          fontSize: 12,
          height: 1.35,
          color: tones.text,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tones.raised,
        surfaceTintColor: Colors.transparent,
        elevation: _floatingElevation,
        shadowColor: tones.shadow,
        shape: floating,
        menuPadding: const EdgeInsets.all(4),
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
          animationDuration: changing,
          shape: const WidgetStatePropertyAll<OutlinedBorder>(rounded),
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
        backgroundColor: tones.raised,
        surfaceTintColor: Colors.transparent,
        elevation: _floatingElevation,
        shadowColor: tones.shadow,
        shape: floating,
        insetPadding: const EdgeInsets.all(24),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        barrierColor: tones.scrim,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tones.raised,
        contentTextStyle: text.bodyMedium?.copyWith(color: tones.text),
        actionTextColor: tones.emphasis,
        shape: floating,
        elevation: _floatingElevation,
        behavior: SnackBarBehavior.floating,
        width: 480,
      ),
      cardTheme: CardThemeData(
        color: tones.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Corners.panelRadius,
          side: BorderSide(color: tones.line),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: Corners.controlRadius,
          side: BorderSide(color: tones.line),
        ),
        backgroundColor: tones.base,
        selectedColor: tones.selection,
        labelStyle: text.labelMedium,
        side: BorderSide(color: tones.line),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tones.raised,
        surfaceTintColor: Colors.transparent,
        elevation: _floatingElevation,
        shadowColor: tones.shadow,
        shape: floating,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: tones.raised,
        elevation: _floatingElevation,
        shadowColor: tones.shadow,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          for (final platform in TargetPlatform.values)
            platform: const FadingPageTransitions(),
        },
      ),
    );
  }

  static MenuStyle _menuStyle(Tones tones, OutlinedBorder floating) =>
      MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(tones.raised),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        elevation: const WidgetStatePropertyAll<double>(_floatingElevation),
        shadowColor: WidgetStatePropertyAll<Color>(tones.shadow),
        shape: WidgetStatePropertyAll<OutlinedBorder>(floating),
        padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.all(4)),
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
    shadow: tones.shadow,
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
