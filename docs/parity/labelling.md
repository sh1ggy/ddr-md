# Editing footing

Hand-set feet pin the parity solve in the chart preview, and are the evidence the engine is tuned against.

1. `flutter run -d macos` (debug builds only), open a chart preview, tap the edit icon top right.
2. The preview jumps to the first flagged moment (doublestep, same panel, footswitch, crossover). Its two rows glow and the rest of the chart dims.
3. Tap a note to swap its foot; the solve re-fits around it. ✓ keeps the moment as it stands and moves on; the arrows step between moments. Reset clears every hand-set foot on the chart (with undo).

Pins live in the app database and pin that chart's preview. Debug builds also mirror each chart's pins to the app's support directory; copy them into the repo to make them tests:

```bash
cp ~/Library/Containers/com.shiggy.ddrmd/Data/Library/Application\ Support/com.shiggy.ddrmd/parity_labels/*.json test/parity_labels/
```

`flutter test test/parity_labels_test.dart` lists every pinned note the unpinned engine disagrees with. Each file carries a hash of the chart's notes; a regenerated chart's labels are reported stale rather than misapplied.
