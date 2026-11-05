# Offline calculated scoring tiers

The phone reads optional `scoring_tiers` from song content. No model or Python
runtime is bundled in the app. Model-only updates do not change the pattern
engine version. Official chart levels and song IDs remain unchanged.

## Environment and model bundle

The production `scoring-v31` macOS bundle and its checksum are retained in the
private [content repository release](https://github.com/sh1ggy/ddr-md-content/releases/tag/scoring-v31).
Restore it from this checkout with access to that repository:

```sh
mkdir -p build
gh release download scoring-v31 --repo sh1ggy/ddr-md-content \
  --pattern 'scoring-v31-macos.*' --dir build
(cd build && shasum -a 256 -c scoring-v31-macos.sha256)
tar -xzf build/scoring-v31-macos.tar.gz -C build
```

The bundle manifest checks the feature sources against the app checkout before
inference. This archive supports macOS; Linux needs a separately frozen and
conformance-checked native bundle. OTA publishing validates the precomputed
ratings without running inference.

Use Python 3.12 in an isolated environment, separately from prep's Poetry env:

```sh
python3.12 -m venv build/scoring-env
build/scoring-env/bin/pip install -r tool/scoring/requirements.txt
cmake -S tool/scoring/native -B build/scoring-native
cmake --build build/scoring-native --parallel 2
```

Freeze a **trusted** fitted checkpoint (joblib is executable Python data), its
passage kernels and the freshly built native library:

```sh
build/scoring-env/bin/python tool/scoring/freeze_bundle.py \
  --checkpoint /path/to/checkpoint/candidate.joblib \
  --kernels /path/to/kernels.npz \
  --native build/scoring-native/libminacalc.dylib \
  --output build/scoring-v31 --version scoring-v31
```

On Linux the library is `libminacalc.so`. `manifest.json` contains immutable
feature source hashes, model/native/kernel checksums, frozen reference CDFs in
the fitted payloads, calibrations and tier widths. All model paths are relative.
Never reuse a version for different weights or rebuild the CDFs while adding
songs. Retain the previous bundle and content for rollback. Bundle archives are
versioned build/release artifacts; do not commit models or binaries to Git.
The vendored native dependency retains its MIT licence in `native/LICENSE.txt`.

## Prep and changed-song runs

From DDR-BPM-prep, after parsing and attaching effective timing:

```sh
make tiers
make tiers SONG='Exact song ID'
make tiers-check
```

`make main` runs tiers before release staging. `SCORING_PYTHON`,
`SCORING_BUNDLE` and `DDR_MD_DIR` can select another isolated environment,
bundle and pinned app checkout. A single-song/chart-fix workflow must run
`make tiers SONG='Exact song ID'` after the final note/timing edit, before copying
the song into the content repo. Never copy the derivative caches to the phone.

Equivalent direct invocation:

```sh
build/scoring-env/bin/python tool/scoring/cli.py \
  --input DDR-BPM-prep/build --bundle build/scoring-v31 \
  --cache DDR-BPM-prep/build/scoring-cache \
  --report DDR-BPM-prep/build/scoring-coverage.json --jobs 2
```

Inputs contain `songs/` and `steps/`. Repeated `--song` options select a subset.
The canonical Dart exporter is run against this checkout; parity and feature
sources must match the frozen bundle. Each native calculation runs in a new
process, always pad then feet, with goals 930, 990, 999 for each.

Cache identities include the selected chart's notes/hold ends, effective
BPM/stop timing, official folder, model version and full feature/bundle identity.
Other charts, song presentation fields and generated annotations are excluded.
Unchanged output is byte-stable. Coverage failures are written to the report;
previously rated charts cannot silently become unrated, even after prep rewrites
the song JSON. `scoring-cache/coverage.json` preserves that inventory across
parses. Retain this cache across `make clobber`.

Fresh input lacking analysable notes can remain unrated. New charts need no
community rating match. Only SP1–19 is supported by this model release.

## Conformance and publishing

Run the dependency-free freshness tests and app regressions:

```sh
python3 -m unittest discover -s tool/scoring/tests -v
flutter test test/scoring_tiers_test.dart test/content_update_test.dart
```

A golden file is a list of chart-only `name`, `difficulty`, `predicted` and
`position` objects from the frozen reference scorer. Do not include labels or
training features. Conformance runs in an isolated overlay and preserves inputs:

```sh
build/scoring-env/bin/python tool/scoring/conformance.py \
  --input /path/to/corpus --bundle build/scoring-v31 \
  --golden /path/to/golden.json --cache build/scoring-conformance-cache \
  --report build/scoring-conformance.json
```

Compare every chart's displayed tier on the production platform, then repeat
with a fresh cache to check repeatability. The default position tolerance is
1e-9; `--position-tolerance` can report a documented cross-platform floating
point tolerance, but displayed tiers must always match exactly. Include timing,
hold and shock charts and every supported folder. A macOS pass alone does not
qualify a Linux bundle for publishing.

For container inference, export canonical derivatives on the pinned Flutter
checkout. `SCORING_CHARTS` is a JSON list of `{name, difficulty}` entries:

```sh
SCORING_INPUT=/path/to/corpus SCORING_CHARTS=/path/to/charts.json \
SCORING_OUTPUT=/path/to/feet.json flutter test tool/export_scoring_features.dart
```

Pass `--derivatives /path/to/feet.json` to the scorer or conformance CLI on
Linux. Keep the adjacent `.metadata.json`, which binds derivatives to the
canonical engine and their output hash. The Dockerfile pins the Python runtime
and numerical packages and builds the native dependency; mount the pinned app
checkout at `/app` and the Linux bundle/inputs as appropriate. Freeze and
conformance-check that Linux bundle before enabling its production use.

Before copying/publishing:

```sh
python3 tool/scoring/validate_content.py --songs assets/songs --steps assets/steps
bash scripts/generate_songlist.sh
```

The existing content workflow validates fingerprints and compares coverage with
the preceding live songlist. It retains optional metadata in the normal songlist;
no new OTA path is needed. Publishing and rollback use the existing content repo
workflow. An app release is needed once for parser/display support; later
compatible model updates are ordinary content publishes.
