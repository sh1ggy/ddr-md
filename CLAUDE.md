# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

DDR MD — a Flutter mobile app for DDR/ITG players: song/chart study (BPM behaviour, scrolling chart preview), personal notes, score tracking, and OCR of cabinet result screens via a native C++ plugin.

## Commands

```bash
flutter pub get                      # install deps
flutter run                          # run the app
flutter analyze                      # lint (flutter_lints)
flutter test                         # all tests
flutter test test/parity_test.dart   # one test file
flutter test --plain-name "substring of test name"   # one test

bash scripts/generate_songlist.sh    # rebuild merged assets/songlist.json — run after ANY change under assets/songs/
bash scripts/build_lite.sh [apk --release]  # build without jackets/per-song JSONs (~430 MB smaller)
bash scripts/init.sh                 # Android only: download OpenCV + ONNX Runtime into native_opencv/.../jniLibs/ (gitignored; rerun after clean checkout)
cd ios && pod install                # iOS native deps (vendored opencv2 + onnxruntime frameworks)
```

Offline OCR harness (desktop, no device needed):

```bash
brew install opencv onnxruntime
cd native_opencv/tools/model_compare && cmake -B build && cmake --build build
./build/model_compare   # sweeps all model tiers over test screenshots → results.csv
```

## Data flow (the big picture)

1. **DDR-BPM-prep/** — a *separate, nested git repo* (Python/poetry pipeline). Scrapes StepMania simfiles, parses BPM/stops/levels/steps, outputs JSON. Do not commit it into this repo. It has its own CODEBASE.md.
2. **assets/songs/*.json** (~1260 files, committed) — the repo's source of truth for song metadata. Parsed into `SongInfo` by [lib/components/song_json.dart](lib/components/song_json.dart) (quicktype-style manual JSON classes).
3. **assets/songlist.json** (gitignored, generated) — all songs merged into one file so startup does 1 asset read instead of ~1100. `Songs.load()` in [lib/models/song_model.dart](lib/models/song_model.dart) prefers it and falls back to per-song files. **A stale songlist.json silently shadows fresh per-song data** — regenerate it after touching assets/songs/.
4. **assets/steps/<name>.json** — per-difficulty note streams. Deliberately NOT merged into the songlist: large, loaded lazily by [lib/models/steps_model.dart](lib/models/steps_model.dart) only when a chart view opens, discarded on close.

## Architecture

- **State**: `provider` ChangeNotifiers. `SongState` ([lib/models/song_model.dart](lib/models/song_model.dart)) holds selected song/mode/difficulty. `Settings` ([lib/models/settings_model.dart](lib/models/settings_model.dart)) is a static wrapper over SharedPreferences with string key constants. Persistent notes/scores go through sqflite ([lib/models/database.dart](lib/models/database.dart), [lib/models/db_models.dart](lib/models/db_models.dart)).
- **Pages** live under `lib/components/<area>/` (song, songlist, ocr, settings); `main.dart` hosts the navigator. Every file opens with a `/// Name: / Parent: / Description:` library doc comment — keep that convention in new files.
- **Chart preview**: [chart_preview_page.dart](lib/components/song/notes/chart_preview_page.dart) is a full-screen route wrapping [chart_scroller.dart](lib/components/song/notes/chart_scroller.dart) (~3400 lines — the scrolling renderer). Playback is driven by wall-clock *seconds carried on each note*, not a reconstructed beat grid, so BPM changes/stops render at true speed. Implements DDR modifiers (TURN/MIRROR, CONSTANT with fade-in, assist tick, the HI-SPEED/SCROLL SPEED speed types) matching official cabinet behaviour — cite the DDR World option semantics in comments when adding modifiers. The speed system was verified against the WORLD binary itself: [docs/ddr-world-speed.md](docs/ddr-world-speed.md). Rendering goes through a pluggable `Noteskin` ([noteskin.dart](lib/components/song/notes/noteskin.dart)): `VectorNoteskin` always works; `SpriteNoteskin` uses copyrighted DDR World sprites from gitignored `assets/noteskin/` and must degrade gracefully when absent (`tryLoad()` returns null). See [docs/noteskin.md](docs/noteskin.md).
- **Parity engine**: [lib/models/parity.dart](lib/models/parity.dart) — a cost-minimising foot-assignment solver ported from SMEditor (heel/toe pad model + forward DP), replacing the old greedy `FootAssigner` in steps_model.dart. Design rationale and port notes: [docs/parity/ANALYSIS.md](docs/parity/ANALYSIS.md). Tests in [test/parity_test.dart](test/parity_test.dart) assert L/R sequences on hand-built streams.
- **OCR**: native C++ in the `native_opencv` path plugin (OpenCV + ONNX Runtime running PaddleOCR PP-OCRv6). Pipeline sources are under `native_opencv/ios/Classes/` and shared with Android via CMake ([ocr_onnx.cpp](native_opencv/ios/Classes/ocr_onnx.cpp) selects the active model tier; small-v6 is default). Dart side: [lib/ocr_processor.dart](lib/ocr_processor.dart) (FFI + isolate, also owns the model-file copy list) and [lib/ocr_config.dart](lib/ocr_config.dart) (field ROIs). **The ROIs in `ocr_config.dart` are mirrored in `makeReferenceConfig()` in [native_opencv/tools/model_compare/main.cpp](native_opencv/tools/model_compare/main.cpp) — change both together.** Only the small-v6 model triplet ships in the app bundle (see pubspec.yaml comments); other tiers exist for the offline model_compare harness.

## Gotchas

- `pubspec.yaml` asset entries carry load-bearing comments (noteskin is optional/gitignored; only one model triplet ships). Don't "clean them up" or blindly add `assets/models/` as a directory.
- Generated/downloaded things that are absent on a fresh clone and must not be committed: `assets/songlist.json`, `assets/noteskin/`, `native_opencv/android/src/main/jniLibs/`, `DDR-BPM-prep/`.
- Shell scripts here inline pure commands — don't extract fetch/copy/check helper functions.
- `docs/` holds design and migration plan docs (OCR engine migrations, parity port, noteskin); check there before re-deriving intent for those subsystems.
