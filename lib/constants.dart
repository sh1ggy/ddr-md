/// Name: Constants
/// Description: A file to store constant values
library;

import 'package:flutter/material.dart';

// FAST/SLOW timing palette, shared by every surface that reports a timing bias:
// the song page's sync card and the chart preview's ARCADE SYNC dials. FAST
// (early / ahead of the beat) reads teal, SLOW (late) reads magenta — one pair
// of colours meaning one pair of things across the app. Each has a darker
// light-mode variant and a brighter dark-mode one so both stay legible.
Color kFastColor(bool isDark) =>
    isDark ? const Color(0xFF46FCE7) : const Color(0xFF00A89E);
Color kSlowColor(bool isDark) =>
    isDark ? const Color(0xFFFF45A0) : const Color(0xFFE53886);

// DDR WORLD's HI-SPEED ladder: the SPEED option was reworked into HI-SPEED,
// x0.25–x8.00 dialled in x0.05 increments (per-song SPEED changes at a song's
// start still move in x0.25 — see _buttonModSteps in chart_scroller). This
// replaces the pre-WORLD x0.25-step ladder. Generated as i/20 so each entry is
// the correctly-rounded double for its decimal (5/20 = 0.25 … 160/20 = 8.0).
final mods = [for (var i = 5; i <= 160; i++) i / 20];
const chosenReadSpeed = 600;
const songBpm = 200;
const rivalCode = "";
const rivalCodeLength = 8;
const username = "";
// In-game dancer names are capped at 8 characters.
const usernameLength = 8;
const maxDifficulty = 19;
const note =
    "The crossovers in this song are surprisingly hard, I keep leading with the wrong first foot in after the jumps. Song should be played with those in mind.";

// DDR releases in chronological order, used for version sorting/filtering.
// These are the bare names the song JSON carries; canonicalVersion() maps the
// display form ("DDR A20 PLUS") onto them.
const versionOrder = [
  'WORLD',
  'A3',
  'A20 PLUS',
  'A20',
  'A',
  '2014',
  '2013',
  'X3',
  'X2',
  'X',
  'SuperNOVA2',
  'SuperNOVA',
  'EXTREME',
  'MAX2',
  'MAX',
  '5th',
  '4th',
  '3rd',
  '2nd',
  '1st',
];

// Version strings reach us both bare from the song JSON ('A20 PLUS', 'WORLD')
// and prefixed from display/user input ('DDR A20 Plus'), so match on a form
// that strips the prefix and ignores case.
String canonicalVersion(String version) {
  final String trimmed = version.trim();
  final String bare = trimmed.toUpperCase().startsWith('DDR ')
      ? trimmed.substring(4).trim()
      : trimmed;
  for (final String known in versionOrder) {
    if (known.toUpperCase() == bare.toUpperCase()) return known;
  }
  return bare;
}

const appVer = "v1.0.1";

// Links
const linkedin = 'https://www.linkedin.com/in/tyrone-nolasco/';
const github = 'https://github.com/sh1ggy';
const paypalDono = 'https://www.paypal.com/donate/?business=Z2967WX5FNN8J&no_recurring=0&item_name=Thank+you+for+supporting+DDR+MD%21&currency_code=AUD';
