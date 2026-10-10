# AGENTS.md

This file provides guidance to coding agents (Claude Code, Codex) when working with code in this repository.

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
flutter test tool/generate_patterns.dart  # rebuild assets/patterns/ + pattern_levels.json (~25 s) — run after changing assets/steps/, parity.dart or pattern_analysis.dart
flutter test tool/content_manifest.dart   # hash content into assets/content_manifest.json, lay out build/content/ (CI runs this to publish)
bash scripts/fetch_content.sh <CONTENT_URL>  # before a store build: make assets/ exactly the live publish
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
2. **assets/songs/*.json** (~1260 files, gitignored — produced by DDR-BPM-prep and kept locally; a fresh clone has none) — the source of truth for song metadata. Parsed into `SongInfo` by [lib/components/song_json.dart](lib/components/song_json.dart) (quicktype-style manual JSON classes).
3. **assets/songlist.json** (gitignored, generated) — all songs merged into one file so startup does 1 asset read instead of ~1100. `Songs.load()` in [lib/models/song_model.dart](lib/models/song_model.dart) prefers it and falls back to per-song files. **A stale songlist.json silently shadows fresh per-song data** — regenerate it after touching assets/songs/.
   `generate_songlist.sh` drops each song's prep `pattern_analysis` (the old v1 analysis, ~10x the rest of the song); the app doesn't read it.
4. **assets/steps/<name>.json** (gitignored, from DDR-BPM-prep) — per-difficulty note streams. Deliberately NOT merged into the songlist: large, loaded lazily by [lib/models/steps_model.dart](lib/models/steps_model.dart) only when a chart view opens, discarded on close.
5. **assets/patterns/<name>.json** (gitignored, generated) — per-chart pattern counts for the song page's Patterns card, read lazily by [lib/models/pattern_model.dart](lib/models/pattern_model.dart). Written only by [tool/generate_patterns.dart](tool/generate_patterns.dart), which runs the app's own parity engine with the Default weights over every chart in assets/steps. Ranks aren't stored per song: `assets/pattern_levels.json` (gitignored, generated) holds every chart's rates by style and level, and the loader ranks against it, so a new song changes only its own file and the table. So the whole directory is stale after any change to the steps, [parity.dart](lib/models/parity.dart) or [pattern_analysis.dart](lib/models/pattern_analysis.dart); [test/patterns_fresh_test.dart](test/patterns_fresh_test.dart) fails until it's regenerated. Files carry `schema` (`kPatternsSchema`); the loader refuses other versions.
6. **Content updates (OTA)** — the songlist, steps, patterns, jackets and parity moments all load through [lib/models/content_store.dart](lib/models/content_store.dart), which reads files downloaded by [lib/models/content_updater.dart](lib/models/content_updater.dart) ahead of the bundle. [tool/content_manifest.dart](tool/content_manifest.dart) hashes the content into `assets/content_manifest.json` and lays out `build/content/` for the URL a build was given with `--dart-define=CONTENT_URL=…` (unset = updates off). Publishing is CI's job: the private `ddr-md-content` repo holds the raw songs/steps/jackets and calls [.github/workflows/publish-content.yml](.github/workflows/publish-content.yml), which generates, continues the content number from the live manifest, and deploys to Cloudflare Pages when anything changed. The live manifest is the only record of the content number, so `assets/content_manifest.json` is gitignored and store builds take it, with the content, from `scripts/fetch_content.sh`. Infra (Pages project, deploy token, content repo, its workflow/secret/variables) is Terraform in `infra/`; never hand-edit the content repo's workflow. The app polls `latest.json`, downloads only files that differ from its bundle, checks each hash and applies them on the next launch. Song `name` is the ID everything keys on (jackets, steps, pins), so never rename one in an update. Bump `kPatternEngineVersion` ([pattern_analysis.dart](lib/models/pattern_analysis.dart)) whenever a parity/pattern change alters the counts, so apps with the old engine keep their own patterns; bump `kContentFormat` if the content's shape changes in a way older apps can't read.

## Architecture

- **State**: `provider` ChangeNotifiers. `SongState` ([lib/models/song_model.dart](lib/models/song_model.dart)) holds selected song/mode/difficulty. `Settings` ([lib/models/settings_model.dart](lib/models/settings_model.dart)) is a static wrapper over SharedPreferences with string key constants. Persistent notes/scores go through sqflite ([lib/models/database.dart](lib/models/database.dart), [lib/models/db_models.dart](lib/models/db_models.dart)).
- **Pages** live under `lib/components/<area>/` (song, songlist, ocr, settings); `main.dart` hosts the navigator. Every file opens with a `/// Name: / Parent: / Description:` library doc comment — keep that convention in new files.
- **Chart preview**: [chart_preview_page.dart](lib/components/song/notes/chart_preview_page.dart) is a full-screen route wrapping [chart_scroller.dart](lib/components/song/notes/chart_scroller.dart) (~3400 lines — the scrolling renderer). Playback is driven by wall-clock *seconds carried on each note*, not a reconstructed beat grid, so BPM changes/stops render at true speed. Implements DDR modifiers (TURN/MIRROR, CONSTANT with fade-in, assist tick, the HI-SPEED/SCROLL SPEED speed types) matching official cabinet behaviour — in comments describe the *behaviour* being reproduced, never how it was determined (see the Provenance rule below). Rendering goes through a pluggable `Noteskin` ([noteskin.dart](lib/components/song/notes/noteskin.dart)): `VectorNoteskin` always works; `SpriteNoteskin` uses copyrighted DDR World sprites from gitignored `assets/noteskin/` and must degrade gracefully when absent (`tryLoad()` returns null). See [docs/noteskin.md](docs/noteskin.md).
- **Parity engine**: [lib/models/parity.dart](lib/models/parity.dart) — a cost-minimising foot-assignment solver ported from SMEditor (heel/toe pad model + forward DP), replacing the old greedy `FootAssigner` in steps_model.dart. Tests in [test/parity_test.dart](test/parity_test.dart) assert L/R sequences on hand-built streams.
- **OCR**: native C++ in the `native_opencv` path plugin (OpenCV + ONNX Runtime running PaddleOCR PP-OCRv6). Pipeline sources are under `native_opencv/ios/Classes/` and shared with Android via CMake ([ocr_onnx.cpp](native_opencv/ios/Classes/ocr_onnx.cpp) selects the active model tier; small-v6 is default). Dart side: [lib/ocr_processor.dart](lib/ocr_processor.dart) (FFI + isolate, also owns the model-file copy list) and [lib/ocr_config.dart](lib/ocr_config.dart) (field ROIs). **The ROIs in `ocr_config.dart` are mirrored in `makeReferenceConfig()` in [native_opencv/tools/model_compare/main.cpp](native_opencv/tools/model_compare/main.cpp) — change both together.** Only the small-v6 model triplet ships in the app bundle (see pubspec.yaml comments); other tiers exist for the offline model_compare harness.

## Provenance (IMPORTANT — keep the repo clean)

- **Never commit reverse-engineering provenance into source or tracked docs.** Committed comments/docs may describe the *behaviour* being reproduced ("REAL SPEED divides by the curated headline BPM", "CONSTANT is a fixed-ms visibility window, k=370 measured from the running game") but MUST NOT include binary/asset provenance: dump filenames or sizes, module names (e.g. `.dll`), virtual addresses / offsets, disassembly (`movzx`/`fdiv`/vtable slots), decompiled function names, proprietary data-file names (e.g. `musicdb.xml`), extracted arcade asset formats/paths (e.g. `.arc`/`.dds`), or specific per-song arcade values used as evidence.
- All such findings live ONLY in the gitignored `_private/` archive (see `.gitignore`). When you discover or need to record a decomp fact, put it there and reference it from source as "notes kept locally" — never inline the finding. If you catch provenance in a diff about to be committed, move it to `_private/` and scrub the tracked copy.

## Gotchas

- `pubspec.yaml` asset entries carry load-bearing comments (noteskin is optional/gitignored; only one model triplet ships). Don't "clean them up" or blindly add `assets/models/` as a directory.
- Generated/downloaded things that are absent on a fresh clone and must not be committed: `assets/songs/`, `assets/steps/`, `assets/patterns/`, `assets/pattern_levels.json`, `assets/content_manifest.json`, `infra/*.tfstate`, `assets/songlist.json`, `assets/noteskin/`, `native_opencv/android/src/main/jniLibs/`, `DDR-BPM-prep/`, `_private/` (RE notes archive), `docs/arcade/`.
- Shell scripts here inline pure commands — don't extract fetch/copy/check helper functions.
- `docs/` holds only how-tos the code relies on (noteskin assets, parity labelling). Plans and design write-ups don't live in the repo.
- `docs/arcade/` (gitignored, kept locally) is the cabinet-behaviour reference. Check it, when present, before claiming or changing anything "arcade accurate". Never commit it or anything else derived from Konami material.
