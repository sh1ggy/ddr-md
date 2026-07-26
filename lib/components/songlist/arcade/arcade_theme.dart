/// Name: arcade_theme
/// Parent: DifficultyListPage, ArcadeGridView
/// Description: The dark cabinet palette the arcade grid renders in, and the
/// ThemeData that restyles the songlist's existing search bar, filter chips
/// and app bar to match it while the grid is on.
library;

import 'package:flutter/material.dart';

// The same near-black the chart preview sits on, so the two arcade-flavoured
// surfaces read as one.
const Color kArcadeBackdrop = Color(0xFF080A0E);

// Cabinet gold: banners, the focused jacket's glow, the SELECT button.
const Color kArcadeAccent = Color(0xFFE8B341);

// One step up from the backdrop, for the info panel and empty jacket cards.
const Color kArcadeSurface = Color(0xFF14181F);

const String kArcadeFont = 'Handel';

/// Dark theme applied over the whole songlist page while the grid is active.
/// Restyling the ambient theme (rather than every control) keeps the shared
/// search bar, filter chips and favourites row legible on the dark backdrop
/// without duplicating them for grid mode.
ThemeData arcadeTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final scheme = base.colorScheme.copyWith(
    primary: kArcadeAccent,
    secondary: kArcadeAccent,
    surface: kArcadeBackdrop,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: kArcadeBackdrop,
    dividerColor: Colors.white24,
    appBarTheme: const AppBarTheme(
      backgroundColor: kArcadeBackdrop,
      foregroundColor: kArcadeAccent,
      elevation: 0,
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStateProperty.all(kArcadeSurface),
      elevation: WidgetStateProperty.all(0),
      textStyle: WidgetStateProperty.all(const TextStyle(color: Colors.white)),
      hintStyle: WidgetStateProperty.all(
          const TextStyle(color: Colors.white38)),
    ),
    searchViewTheme: const SearchViewThemeData(
      backgroundColor: kArcadeBackdrop,
      dividerColor: Colors.white24,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: kArcadeSurface,
      selectedColor: kArcadeAccent.withValues(alpha: 0.25),
      labelStyle: const TextStyle(color: Colors.white),
      side: const BorderSide(color: Colors.white24),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Colors.white,
      iconColor: kArcadeAccent,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
    ),
  );
}
