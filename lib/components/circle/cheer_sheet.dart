/// Name: CheerSheet
/// Parent: CircleCreditCard
/// Description: Cheering a credit: its player and songs at the top, then the
/// six cheers as big tilted stamps to slap on it. Picking one closes the
/// sheet with a buzz and a burst of confetti from the Cheer button; picking
/// your own again, or Take it back, removes it.
library;

import 'package:ddr_md/components/circle/cheer_stamp.dart';
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// [button] is the Cheer button the confetti bursts from. [summary] says
/// what's cheered when it's more than [credit] alone, as for a session.
Future<void> showCheerSheet(BuildContext button, CircleCredit credit,
    {String? summary}) {
  final circle = button.read<CircleState>();
  final box = button.findRenderObject() as RenderBox?;
  final from = box?.localToGlobal(box.size.center(Offset.zero));
  var sending = false;
  String? error;
  return showModalBottomSheet(
    context: button,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(builder: (sheet, setState) {
      final pop = FloorPop.of(sheet);
      Future<void> pick(Cheer? cheer) async {
        if (sending) return;
        setState(() {
          sending = true;
          error = null;
        });
        final sent = await circle.cheerFor(credit, cheer);
        if (!sheet.mounted) return;
        if (!sent) {
          setState(() {
            sending = false;
            error = "Your cheer didn't send. Tap a stamp to try again.";
          });
          return;
        }
        // The initial Cheer button disappears once your note is attached;
        // use the still-mounted sheet's overlay for the success effect.
        if (cheer != null) {
          HapticFeedback.mediumImpact();
          if (from != null) burstConfetti(sheet, from, cheer);
        }
        Navigator.pop(sheet);
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CheerIcon(size: 34),
                const SizedBox(height: 8),
                Text('Cheer ${credit.by!.name}',
                    style: FloorPop.display(20,
                        color: Theme.of(sheet).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                    summary ??
                        'Credit ${credit.credit} · '
                            '${credit.plays.length} songs'
                            '${credit.plays.any((p) => p.best && !p.failed) ? ' · new best!' : ''}',
                    style: TextStyle(color: pop.haze)),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.6,
                  children: [
                    for (final cheer in Cheer.values)
                      _StampButton(
                        cheer,
                        chosen: credit.mine == cheer,
                        onTap: sending
                            ? null
                            : () => pick(credit.mine == cheer ? null : cheer),
                      ),
                  ],
                ),
                if (sending) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(sheet).colorScheme.error)),
                if (credit.mine != null)
                  TextButton(
                    onPressed: sending ? null : () => pick(null),
                    child: const Text('Take my cheer back'),
                  ),
              ])),
        ),
      );
    }),
  );
}

class _StampButton extends StatelessWidget {
  const _StampButton(this.cheer, {required this.chosen, required this.onTap});
  final Cheer cheer;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: chosen,
        label: cheer.label,
        child: GestureDetector(
          onTap: onTap,
          child: Center(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Stack(clipBehavior: Clip.none, children: [
                  CheerStamp(cheer, large: true),
                  if (chosen)
                    Positioned(
                      right: -6,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.check_circle,
                            size: 18, color: FloorPop.onVolt),
                      ),
                    ),
                ])),
          ),
        ),
      );
}
