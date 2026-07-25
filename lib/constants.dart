/// Name: Constants
/// Description: A file to store constant values
library;

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
const versionOrder = [
  'DDR World',
  'DDR A3',
  'DDR A20 PLUS',
  'DDR A20',
  'DDR A',
  'DDR 2014',
  'DDR 2013',
  'DDR X3',
  'DDR X2',
  'DDR X',
  'DDR SuperNOVA2',
  'DDR SuperNOVA',
  'DDR EXTREME',
  'DDR MAX2',
  'DDR MAX',
  'DDR 5th',
  'DDR 4th',
  'DDR 3rd',
  'DDR 2nd',
  'DDR',
];

const appVer = "v1.0.1";

// Links
const linkedin = 'https://www.linkedin.com/in/tyrone-nolasco/';
const github = 'https://github.com/sh1ggy';
const paypalDono = 'https://www.paypal.com/donate/?business=Z2967WX5FNN8J&no_recurring=0&item_name=Thank+you+for+supporting+DDR+MD%21&currency_code=AUD';
