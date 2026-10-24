/// Name: Theme
/// Parent: App
/// Description: Floor Pop, the app's look: a dark violet stage (and a light
/// Day variant), one Volt accent for the primary action and selection,
/// Unbounded for titles, Inter for text and Chakra Petch italic for the
/// numbers the app computes. Chart levels, difficulty names, lamps, grades
/// and style icons stay the game's own art; this only styles around them.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

const kDisplayFont = 'Unbounded';
const kTextFont = 'Inter';
const kReadoutFont = 'ChakraPetch';

/// Floor Pop's colours and measures beyond the [ColorScheme].
@immutable
class FloorPop extends ThemeExtension<FloorPop> {
  const FloorPop({
    required this.ink,
    required this.stage,
    required this.riser,
    required this.line,
    required this.haze,
    required this.stripe,
    required this.voltText,
    required this.up,
    required this.down,
  });

  final Color ink, stage, riser, line, haze, stripe;
  // Volt as text, darkened on Day where the fill would not read.
  final Color voltText;
  // Above and below your usual.
  final Color up, down;

  static const volt = Color(0xFFC8F031);
  // The hard edge under a Volt button, collapsing on press.
  static const voltRiser = Color(0xFF7E9A12);
  static const onVolt = Color(0xFF16122C);
  static const padBlue = Color(0xFF4D6BFF);
  static const coral = Color(0xFFFF4F6E);
  static const sun = Color(0xFFFFC43D);
  static const grape = Color(0xFFA160FF);

  /// The one lean, on chips and page titles: −12° (titles take −8°).
  static final lean = Matrix4.skewX(-math.tan(12 * math.pi / 180));
  static final titleLean = Matrix4.skewX(-math.tan(8 * math.pi / 180));

  /// Motion runs on a 150 BPM grid.
  static const sixteenth = Duration(milliseconds: 100);
  static const eighth = Duration(milliseconds: 200);
  static const beat = Duration(milliseconds: 400);
  static const step = Cubic(0.2, 0.9, 0.25, 1.1);

  static const night = FloorPop(
    ink: Color(0xFF0E0B1F),
    stage: Color(0xFF19152F),
    riser: Color(0xFF231E42),
    line: Color(0xFF2C2650),
    haze: Color(0xFFA9A3CC),
    stripe: Color(0x0BFFFFFF),
    voltText: volt,
    up: Color(0xFF3DDC84),
    down: coral,
  );

  static const day = FloorPop(
    ink: Color(0xFFF4F2FB),
    stage: Color(0xFFFFFFFF),
    riser: Color(0xFFECE9F8),
    line: Color(0xFFDDD8F0),
    haze: Color(0xFF5B5580),
    stripe: Color(0x0D16122C),
    voltText: Color(0xFF4E6B00),
    up: Color(0xFF1E9E5A),
    down: Color(0xFFD93354),
  );

  static FloorPop of(BuildContext context) =>
      Theme.of(context).extension<FloorPop>()!;

  /// A number the app computes: score, BPM, speed, timing.
  static TextStyle readout(double size, {Color? color}) => TextStyle(
        fontFamily: kReadoutFont,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w700,
        fontSize: size,
        height: 1.05,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle display(double size, {Color? color}) => TextStyle(
        fontFamily: kDisplayFont,
        fontWeight: FontWeight.w900,
        fontSize: size,
        height: 1.05,
        color: color,
      );

  /// A section label over a card's content: small caps, tracked out.
  TextStyle get label => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.3,
      color: haze);

  /// Faint speed stripes at 115°, behind hero headers.
  BoxDecoration stripes({Color? color, BorderRadius? radius}) => BoxDecoration(
        color: color,
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(-0.985, -0.993),
          tileMode: TileMode.repeated,
          colors: [stripe, stripe, Colors.transparent, Colors.transparent],
          stops: const [0, 0.14, 0.14, 1],
        ),
      );

  @override
  FloorPop copyWith() => this;

  @override
  FloorPop lerp(FloorPop? other, double t) => t < 0.5 ? this : other ?? this;
}

ThemeData floorPopTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final pop = dark ? FloorPop.night : FloorPop.day;
  final text = dark ? const Color(0xFFF4F1FF) : const Color(0xFF16122C);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? FloorPop.volt : const Color(0xFF3352E0),
    onPrimary: dark ? FloorPop.onVolt : Colors.white,
    secondary: FloorPop.padBlue,
    onSecondary: Colors.white,
    tertiary: FloorPop.grape,
    onTertiary: FloorPop.onVolt,
    error: pop.down,
    onError: Colors.white,
    surface: pop.ink,
    onSurface: text,
    onSurfaceVariant: pop.haze,
    surfaceContainerLowest: pop.ink,
    surfaceContainerLow: pop.stage,
    surfaceContainer: pop.stage,
    surfaceContainerHigh: pop.riser,
    surfaceContainerHighest: pop.riser,
    outline: pop.line,
    outlineVariant: pop.line,
    primaryContainer: FloorPop.volt,
    onPrimaryContainer: FloorPop.onVolt,
    secondaryContainer: pop.riser,
    onSecondaryContainer: text,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kTextFont,
    scaffoldBackgroundColor: pop.ink,
    canvasColor: pop.ink,
    dividerColor: pop.line,
    extensions: [pop],
  );
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineMedium: FloorPop.display(26, color: text),
      titleLarge: FloorPop.display(20, color: text)
          .copyWith(fontWeight: FontWeight.w700),
      titleMedium:
          TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: text),
      titleSmall:
          TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: text),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: pop.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: text,
      iconTheme: IconThemeData(color: text),
      titleTextStyle: FloorPop.display(22, color: text),
    ),
    cardTheme: CardThemeData(
      color: pop.stage,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FloorPop.volt,
        foregroundColor: FloorPop.onVolt,
        minimumSize: const Size(48, 48),
        shape: round,
        textStyle: const TextStyle(
            fontFamily: kTextFont, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: pop.line, width: 1.5),
        minimumSize: const Size(44, 44),
        shape: round,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? FloorPop.volt : scheme.primary,
        textStyle:
            const TextStyle(fontFamily: kTextFont, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FloorPop.volt,
      foregroundColor: FloorPop.onVolt,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(round),
        side: WidgetStatePropertyAll(BorderSide(color: pop.line)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? text : pop.riser),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? pop.ink : pop.haze),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: kTextFont, fontWeight: FontWeight.w700)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: pop.riser,
      selectedColor: FloorPop.volt,
      secondarySelectedColor: FloorPop.volt,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
          fontFamily: kTextFont, fontWeight: FontWeight.w600, color: text),
      secondaryLabelStyle: const TextStyle(
          fontFamily: kTextFont,
          fontWeight: FontWeight.w600,
          color: FloorPop.onVolt),
      checkmarkColor: FloorPop.onVolt,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pop.riser,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      hintStyle: TextStyle(color: pop.haze),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(pop.riser),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(round),
      hintStyle: WidgetStatePropertyAll(TextStyle(color: pop.haze)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: pop.stage,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: pop.stage,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: FloorPop.display(18, color: text)
          .copyWith(fontWeight: FontWeight.w700),
    ),
    listTileTheme: ListTileThemeData(iconColor: pop.haze),
    dividerTheme: DividerThemeData(color: pop.line, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: text,
      contentTextStyle: TextStyle(color: pop.ink, fontFamily: kTextFont),
      actionTextColor: dark ? const Color(0xFF4E6B00) : FloorPop.volt,
      behavior: SnackBarBehavior.floating,
      shape: round,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: text,
      unselectedLabelColor: pop.haze,
      indicatorColor: dark ? FloorPop.volt : scheme.primary,
      dividerColor: pop.line,
      labelStyle:
          const TextStyle(fontFamily: kTextFont, fontWeight: FontWeight.w700),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? FloorPop.onVolt : pop.haze),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? FloorPop.volt : pop.riser),
      trackOutlineColor: WidgetStatePropertyAll(pop.line),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? FloorPop.volt : scheme.primary),
  );
}
