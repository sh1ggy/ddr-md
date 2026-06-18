# Plan: Japanese-capable detection via PP-OCRv3 mobile det

## Goal

Make text detection robust on Japanese DDR screens (song titles, usernames). The current detector — `assets/models/ppocr_mobile_det.onnx`, loaded by [ocr_onnx.cpp:128-136](native_opencv/ios/Classes/ocr_onnx.cpp#L128-L136) — was sourced as a generic latin-leaning DB checkpoint and tends to miss or split Japanese glyph runs in title/username ROIs.

PaddleOCR's detector is language-agnostic in architecture (DB segmentation of any "ink-on-background"), but the published checkpoints differ in training corpus mix. The HuggingFace card [PaddlePaddle/PP-OCRv3_mobile_det](https://huggingface.co/PaddlePaddle/PP-OCRv3_mobile_det) ships a multilingual-trained DB detector explicitly aimed at CJK + latin.

Recognition is already EngJP-capable: `ppocrv5_dict.txt` is the PP-OCRv5 18,384-entry multilingual dict and the rec model passes JP through. The bottleneck for JP titles is the detector cutting off or merging the line.

## Scope (what this plan is NOT)

This plan only swaps the detection checkpoint. It does **not**:
- Change the recogniser (covered by [plan-paddle-v6-migration.md](plan-paddle-v6-migration.md))
- Change preprocessing constants, postprocess thresholds, or the DB pipeline in [ocr_onnx.cpp:279-457](native_opencv/ios/Classes/ocr_onnx.cpp#L279-L457)
- Add a Japanese-specific code path in C++ — the model is drop-in compatible

## Steps

### 1. Obtain the model

Source: `https://huggingface.co/PaddlePaddle/PP-OCRv3_mobile_det`. Files are in PIR Paddle format (`inference.json` + `inference.pdiparams`). The Hugging Face mirror also exposes raw downloads.

Two routes:

**A. Pre-converted ONNX (preferred).** Check `https://huggingface.co/AIPLUX/paddleocr-ppocrv3-onnx` or `rapidocr` releases for a `ppocrv3_mobile_det.onnx` artifact. If found, skip step 1B.

**B. Convert with paddle2onnx:**
```
pip install paddle2onnx
paddle2onnx --model_dir ./PP-OCRv3_mobile_det \
  --model_filename inference.json \
  --params_filename inference.pdiparams \
  --save_file ppocr_mobile_det_v3_jp.onnx \
  --opset_version 11 \
  --enable_onnx_checker True
```

Same PIR-format flag as [plan-paddle-det-integration.md:23-32](docs/plan-paddle-det-integration.md#L23-L32) — `inference.json`, not `.pdmodel`.

### 2. Verify preprocessing compatibility

Open `inference.yml` from the checkpoint dir and confirm against [ocr_onnx.cpp:281-305](native_opencv/ios/Classes/ocr_onnx.cpp#L281-L305):

- `limit_side_len: 960` — already matches `DET_LIMIT_SIDE_LEN`
- Normalisation: `mean=[0.485,0.456,0.406]` / `std=[0.229,0.224,0.225]` — matches `MEAN`/`STD` constants
- Channel order: **RGB after BGR→RGB swap** — matches current code at [ocr_onnx.cpp:362-368](native_opencv/ios/Classes/ocr_onnx.cpp#L362-L368)
- `thresh: 0.3`, `box_thresh: 0.6` — current `DET_BIN_THRESHOLD = 0.3f` matches the threshold; the code doesn't apply a separate `box_thresh` (it picks every contour above bin threshold). Leave as-is unless the v3 model floods false-positives.

If `inference.yml` disagrees on any of the above, prefer the yaml over the code constants — wrong norm silently kills detection.

### 3. Drop in the model

Replace the file at `assets/models/ppocr_mobile_det.onnx`. Keep the filename so:
- [ocr_onnx.cpp:93](native_opencv/ios/Classes/ocr_onnx.cpp#L93) — `detPath` resolution stays the same
- [ocr_processor.dart:520](lib/ocr_processor.dart#L520) — asset copy list stays the same
- `pubspec.yaml:38` — `assets/models/` directory inclusion already covers it

No code changes needed if filename is preserved.

### 4. Smoke test

1. Build for one platform (iOS or Android — same model file works on both).
2. Feed in a DDR result screen that has a Japanese song title.
3. With debug toggle ON, inspect `paddle_detect.png` (written by [ocr_onnx.cpp:580-582](native_opencv/ios/Classes/ddrocr_instance.cpp#L580-L582)) for the combined score panel — boxes should still wrap the digits correctly.
4. Inspect `roi_title.png` + the per-box OCR debug crops: the title box should now wrap the full Japanese string without splitting kanji runs or clipping kana tails.

### 5. Regression check on existing English path

If the new detector behaves differently on numeric panels (e.g. splits "100,000" into two boxes), the field-picker in [ddrocr_instance.cpp:587-617](native_opencv/ios/Classes/ddrocr_instance.cpp#L587-L617) — which picks the single best-overlap detection per field anchor — will likely still pick correctly, since field anchors are coarse. If it doesn't, the fallback is to keep both detectors (load v3-jp into a second `Ort::Session`, route title/username through it, route the score panel through the existing v5 det). Don't pre-empt that; do it only if smoke testing shows real regression.

## Common pitfalls

- **Skipping `inference.yml` check.** Different PaddleOCR det checkpoints have different `limit_side_len` (sometimes 736, sometimes 1280) and slightly different unclip ratios. Read the yaml shipped with the model.
- **Assuming PP-OCRv3 multilingual det is "better" everywhere.** It's tuned for CJK-heavy mixes; on pure numeric panels it may produce slightly tighter or noisier boxes. That's the regression check in step 5.
- **Forgetting Android.** The model lives in `assets/models/` and is copied to writable storage at startup ([ocr_processor.dart:517-535](lib/ocr_processor.dart#L517-L535)). The same file works for both platforms — no per-platform copies.

## Files modified

- `assets/models/ppocr_mobile_det.onnx` — replace bytes (~5 MB)

No code changes if filename is preserved.
