# Plan: Migrate PaddleOCR v5 → v6 tiny (det + rec)

## Goal

Move both the detection and recognition models from PP-OCRv5 mobile to **PP-OCRv6 tiny**:

- [PP-OCRv6_tiny_det_onnx](https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx) — drop-in replacement for the current det model
- [PP-OCRv6_tiny_rec_onnx](https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx) — drop-in replacement for the current rec model

The "tiny" variants are mobile-targeted and ship pre-converted to ONNX, so no `paddle2onnx` step is needed.

Today's setup, for reference:
- Rec session: [ocr_onnx.cpp:113-115](native_opencv/ios/Classes/ocr_onnx.cpp#L113-L115) loads `ppocr_mobile_rec.onnx`, preprocesses to NCHW 1×3×48×320 with `(x/255-0.5)/0.5` at [ocr_onnx.cpp:162-204](native_opencv/ios/Classes/ocr_onnx.cpp#L162-L204), input name hardcoded `"x"`, output name hardcoded `"fetch_name_0"` ([ocr_onnx.cpp:212-213](native_opencv/ios/Classes/ocr_onnx.cpp#L212-L213)).
- Dict: [ocr_onnx.cpp:94-105](native_opencv/ios/Classes/ocr_onnx.cpp#L94-L105) reads `ppocrv5_dict.txt`, blank=0, classes shift +1.
- Det session: [ocr_onnx.cpp:128-136](native_opencv/ios/Classes/ocr_onnx.cpp#L128-L136) loads `ppocr_mobile_det.onnx`, runtime-discovers input/output names at [ocr_onnx.cpp:379-383](native_opencv/ios/Classes/ocr_onnx.cpp#L379-L383). Already robust to renames.
- Asset copy list: [ocr_processor.dart:518-523](lib/ocr_processor.dart#L518-L523).

The two unknowns we have to resolve from each model's `inference.yml` / model card before writing code:

1. **Rec input height.** PP-OCRv6 may have moved from 48 to 32 (some variants did) or kept 48. The current code hardcodes `TARGET_H = 48` at [ocr_onnx.cpp:166](native_opencv/ios/Classes/ocr_onnx.cpp#L166).
2. **Rec dict.** PP-OCRv6 ships its own dict. The class-count must match the recogniser's final-layer dim; using v5's dict against v6's logits will silently produce garbage.
3. **Rec normalisation.** v5 uses `(x/255-0.5)/0.5`. v6 *may* still use that — verify against the v6 yaml. If it's switched to ImageNet norm (unlikely for rec, but check), the preprocess loop must change.
4. **Rec output layout.** Today decoded as `[B, T, C]` ([ocr_onnx.cpp:229-236](native_opencv/ios/Classes/ocr_onnx.cpp#L229-L236)). If v6 outputs `[B, C, T]`, the CTC decode reads the wrong stride.

Resolve these four before touching code; everything else is mechanical.

## Steps

### 1. Download the ONNX artifacts

From each HF repo's "Files and versions":
- `PP-OCRv6_tiny_det_onnx` → grab the `.onnx` file and the accompanying `inference.yml` (or model card)
- `PP-OCRv6_tiny_rec_onnx` → grab the `.onnx`, the dict (`ppocrv6_dict.txt` or similar), and `inference.yml`

Don't commit yet — first verify the four unknowns above by reading the yamls.

### 2. Resolve the four unknowns

Open each `inference.yml` and record:

| Setting | v5 (current) | v6 tiny | Source |
|---|---|---|---|
| Rec input H | 48 | ? | rec `inference.yml` `image_shape` |
| Rec input W (max) | 320 | ? | rec `inference.yml` `max_text_length` × char_width or `image_shape` |
| Rec normalisation | `(x/255-0.5)/0.5` | ? | rec `inference.yml` `NormalizeImage` block |
| Rec output layout | `[B,T,C]` | ? | inspect the ONNX with `python -c "import onnx; print(onnx.load('rec.onnx').graph.output)"` |
| Dict size | 18384 lines | ? | line-count `ppocrv6_*dict.txt` |
| Det `limit_side_len` | 960 | ? | det `inference.yml` |
| Det normalisation | ImageNet | ? | det `inference.yml` |
| Det thresholds | thresh 0.3, box 0.6 | ? | det `inference.yml` |

If any rec value changed, the code in [ocr_onnx.cpp:162-258](native_opencv/ios/Classes/ocr_onnx.cpp#L162-L258) needs an edit. If any det value changed, the constants at [ocr_onnx.cpp:281-285](native_opencv/ios/Classes/ocr_onnx.cpp#L281-L285) need an edit.

### 3. Add the new assets alongside the old (don't delete yet)

Drop into `assets/models/`:
- `ppocr_tiny_det.onnx`
- `ppocr_tiny_rec.onnx`
- `ppocrv6_dict.txt` (or whatever name the rec repo ships)

Keep `ppocr_mobile_det.onnx`, `ppocr_mobile_rec.onnx`, `ppocrv5_dict.txt` in place during validation so you can flip back by changing one string.

`pubspec.yaml:38` already includes `assets/models/` as a directory — no manifest edit needed.

Add the three new paths to the copy list at [ocr_processor.dart:518-523](lib/ocr_processor.dart#L518-L523):

```dart
const assets = [
  'assets/templates/details.png',
  'assets/models/ppocr_mobile_det.onnx',     // v5 (leave for rollback)
  'assets/models/ppocr_mobile_rec.onnx',     // v5 (leave for rollback)
  'assets/models/ppocrv5_dict.txt',          // v5 (leave for rollback)
  'assets/models/ppocr_tiny_det.onnx',       // v6
  'assets/models/ppocr_tiny_rec.onnx',       // v6
  'assets/models/ppocrv6_dict.txt',          // v6
];
```

### 4. Point the C++ loader at v6

In [ocr_onnx.cpp:92-94](native_opencv/ios/Classes/ocr_onnx.cpp#L92-L94):

```cpp
std::string modelPath = dataPath + "/models/ppocr_tiny_rec.onnx";
std::string detPath   = dataPath + "/models/ppocr_tiny_det.onnx";
std::string dictPath  = dataPath + "/models/ppocrv6_dict.txt";
```

Three string changes. Nothing else in the loader needs to move — the model-load and dict-load logic doesn't care about version.

### 5. Apply any preprocessing deltas from step 2

For each row in the table where v6 differs from v5:

- **Rec input H or W changed** → update `TARGET_H` / `TARGET_W` constants at [ocr_onnx.cpp:166-167](native_opencv/ios/Classes/ocr_onnx.cpp#L166-L167). The aspect-preserving resize at [ocr_onnx.cpp:187-189](native_opencv/ios/Classes/ocr_onnx.cpp#L187-L189) and the padding-fill constant at [ocr_onnx.cpp:194](native_opencv/ios/Classes/ocr_onnx.cpp#L194) follow automatically.
- **Rec norm changed** → update the per-pixel formula inside the loop at [ocr_onnx.cpp:202](native_opencv/ios/Classes/ocr_onnx.cpp#L202). Update the pad fill at [ocr_onnx.cpp:194](native_opencv/ios/Classes/ocr_onnx.cpp#L194) to match `(0 - mean) / std` per channel (single scalar only works if mean+std are channel-uniform).
- **Rec output layout `[B,C,T]` instead of `[B,T,C]`** → rewrite `ctcDecode` ([ocr_onnx.cpp:35-69](native_opencv/ios/Classes/ocr_onnx.cpp#L35-L69)) to step `C` strides over `T` rather than vice versa. The cleanest fix is to transpose the read indexing: `row = logits + t` and `row[c * seqLen]` instead of `row + t * numClasses` and `row[c]`. Easy to get wrong; add an assert that argmax of timestep 0 isn't always 0.
- **Det `limit_side_len` changed** → update `DET_LIMIT_SIDE_LEN` ([ocr_onnx.cpp:281](native_opencv/ios/Classes/ocr_onnx.cpp#L281)).
- **Det norm changed** → update `MEAN`/`STD` ([ocr_onnx.cpp:352-353](native_opencv/ios/Classes/ocr_onnx.cpp#L352-L353)) or the channel-swap at [ocr_onnx.cpp:362-368](native_opencv/ios/Classes/ocr_onnx.cpp#L362-L368).
- **Det `box_thresh` is now enforced** → the current code doesn't apply a per-box score threshold (only the bin threshold + min-area filter at [ocr_onnx.cpp:417, 433](native_opencv/ios/Classes/ocr_onnx.cpp#L417)). If v6 needs it, compute mean prob inside the contour's axis-aligned bbox and discard if `< box_thresh`. Pattern is in [docs/plan-paddle-det-integration.md:84-104](docs/plan-paddle-det-integration.md#L84-L104).

### 6. Validate rec output indexing

Easy silent-failure mode if the v6 rec layout flips: text decodes as repeated blanks or one repeated character.

Sanity check on first build:
- Pick a known crop (e.g. saved `roi_combined.png` from a previous debug run).
- Run it through the new pipeline.
- If output is empty / garbage, log the first-timestep argmax and the shape values `seqLen`/`numClasses`. If `numClasses` is suspiciously small (~80) or huge (~30000), the dimensions are swapped.

### 7. Smoke-test on real DDR data

Same protocol as [plan-paddle-det-integration.md:144-149](docs/plan-paddle-det-integration.md#L144-L149):
1. Feed a result screenshot. Confirm score panel digits decode.
2. Confirm title/username decodes (use a Japanese-title screenshot if Japanese support is in scope — coordinate with [plan-japanese-detection.md](plan-japanese-detection.md), and prefer one detector swap at a time).
3. Log per-stage timings. Tiny should be **faster** than mobile. If it's slower, something's wrong (likely the rec input grew or the det side increased).

### 8. Remove v5 once v6 is proven

After at least one round-trip of validation (build + manual test on both iOS and Android):
- Delete `assets/models/ppocr_mobile_det.onnx`, `ppocr_mobile_rec.onnx`, `ppocrv5_dict.txt`.
- Drop those three lines from the copy list at [ocr_processor.dart:518-523](lib/ocr_processor.dart#L518-L523).
- Leave a single short note in `CHANGELOG.md` or the commit message — no doc-level migration trail needed.

## Common pitfalls

- **Dict / model mismatch.** v6 rec output channels are determined by v6's dict size + 1 (for blank). If you ship v6 rec with v5's dict, CTC decode runs without crashing but every character will be wrong. The `numClasses` log line at decode time is your canary.
- **Forgetting blank=0 convention.** If v6 happens to put blank at the end (some non-Paddle exports do), `BLANK_IDX = 0` ([ocr_onnx.cpp:17](native_opencv/ios/Classes/ocr_onnx.cpp#L17)) flips. Confirm from the v6 model card.
- **Output-name brittleness.** Rec still hardcodes `"fetch_name_0"` ([ocr_onnx.cpp:213](native_opencv/ios/Classes/ocr_onnx.cpp#L213)). v6 will almost certainly use a different name. Either update to the new name, or switch to `GetOutputNameAllocated(0, alloc)` like the det path already does. Prefer the latter — one less hardcode.
- **Validating with debug builds only.** `save_img` short-circuits under `NDEBUG` ([ddrocr_instance.cpp:20-21](native_opencv/ios/Classes/ddrocr_instance.cpp#L20-L21)). If your release build behaves differently from debug after the swap, it's not the model — it's something gated on `NDEBUG`.
- **Doing both Japanese-detector and v6 migrations in one pass.** Each changes detection behaviour. If a regression appears, you won't know which swap caused it. Land them as two commits.

## Files modified

- `assets/models/ppocr_tiny_det.onnx` (new)
- `assets/models/ppocr_tiny_rec.onnx` (new)
- `assets/models/ppocrv6_dict.txt` (new)
- `lib/ocr_processor.dart` — copy-list edits
- `native_opencv/ios/Classes/ocr_onnx.cpp` — path strings; preprocessing deltas (if any); rec output-name lookup; possibly CTC layout

No `.h`, no build-system, no FFI signature changes.
