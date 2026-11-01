/// Name: CircleSheets
/// Parent: CirclePage
/// Description: The Circle tab's sheets and pages: your invite QR with its
/// code written under it (copy, share, a new one; each lasts a day), joining
/// by scanning someone's QR or typing their code, leaving someone's circle or
/// taking them out of yours, and your name and DDR-CODE with the way to
/// delete it all.
library;

import 'package:ddr_md/components/circle/circle_explainer.dart';
import 'package:ddr_md/components/circle/circle_page.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/session_page.dart' show confirmDelete;
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

const _bold =
    TextStyle(fontFamily: kTextFont, fontSize: 15, fontWeight: FontWeight.w700);

Future<void> showInviteSheet(BuildContext context) {
  final circle = context.read<CircleState>();
  if (!circle.codeLive) circle.newCode();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => const _InviteSheet(),
  );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  // Copy says so on the button itself: a snackbar would sit under the sheet.
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final pop = FloorPop.of(context);
    final code = circle.codeLive ? circle.code! : null;
    final left = circle.codeUntil?.difference(DateTime.now());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Scan each other',
                style: FloorPop.display(20,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 6),
            Text(
                "Have them scan this, or scan theirs. One scan and you're "
                'friends, cheering each other on.',
                style: TextStyle(color: pop.haze, height: 1.4)),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 232,
                height: 232,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24)),
                child: code == null
                    ? Center(
                        child: circle.loading
                            ? const CircularProgressIndicator()
                            : Text(circle.error,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black)))
                    : QrImageView(
                        data: circleQrData(code),
                        padding: EdgeInsets.zero,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: FloorPop.onVolt),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: FloorPop.onVolt),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            // The code under the QR, to read out or type when a camera can't.
            Center(
              child: SelectableText(code == null ? '' : formatCircleCode(code),
                  style: FloorPop.readout(30, color: pop.voltText)),
            ),
            if (left != null && code != null)
              Center(
                child: Text(
                    left.inHours >= 1
                        ? 'Works for ${left.inHours + 1} more hours'
                        : 'Works for ${left.inMinutes + 1} more minutes',
                    style: TextStyle(color: pop.haze, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: code == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                              ClipboardData(text: formatCircleCode(code)));
                          setState(() => _copied = true);
                          await Future.delayed(const Duration(seconds: 2));
                          if (mounted) setState(() => _copied = false);
                        },
                  child: Text(_copied ? 'Copied' : 'Copy code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (button) => OutlinedButton(
                    onPressed: code == null
                        ? null
                        : () {
                            final box = button.findRenderObject() as RenderBox?;
                            SharePlus.instance.share(ShareParams(
                              text: 'Join my circle on DDR MD with code '
                                  '${formatCircleCode(code)} '
                                  '(Circle tab → scan, or type it in)',
                              sharePositionOrigin: box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size,
                            ));
                          },
                    child: const Text('Share'),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            VoltButton(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .pushReplacement(MaterialPageRoute(
                      builder: (_) => const JoinCirclePage())),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code_scanner, size: 20),
                SizedBox(width: 8),
                Text('Scan theirs', style: _bold),
              ]),
            ),
            TextButton(
              onPressed: circle.loading ? null : circle.newCode,
              child: const Text('Make a new code'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openJoinCircle(BuildContext context) =>
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => const JoinCirclePage()));

/// Scanning someone's invite QR, or typing its code when the camera can't,
/// then seeing whose circle it opens and joining.
class JoinCirclePage extends StatefulWidget {
  const JoinCirclePage({super.key});

  @override
  State<JoinCirclePage> createState() => _JoinCirclePageState();
}

class _JoinCirclePageState extends State<JoinCirclePage> {
  final _field = TextEditingController();
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  CirclePreview? _preview;
  String? _code;

  @override
  void dispose() {
    _field.dispose();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _find(String code) async {
    if (code == _code && _preview != null) return;
    _code = code;
    final preview = await context.read<CircleState>().preview(code);
    if (!mounted) return;
    setState(() => _preview = preview);
    if (preview != null) _scanner.stop();
  }

  // In their circle now: the page turns to the other half of the swap.
  bool _joined = false;
  // Letting them into yours as you join: friends in one scan, unless unticked.
  bool _back = true;

  Future<void> _join() async {
    final circle = context.read<CircleState>();
    if (!await circle.join(_code!, back: _back) || !mounted) return;
    setState(() => _joined = true);
  }

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final pop = FloorPop.of(context);
    final preview = _preview;
    final typed = findCircleCode(_field.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan theirs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (_joined && preview != null)
            _Joined(preview.leader,
                friends: circle.following
                        .where((p) => p.id == preview.leader.id)
                        .firstOrNull
                        ?.friend ??
                    false)
          else if (preview == null) ...[
            // Square, but small enough on a wide window to leave the typed
            // code in view.
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: MobileScanner(
                          controller: _scanner,
                          onDetect: (capture) {
                            final code = capture.barcodes
                                .map((b) => findCircleCode(b.rawValue ?? ''))
                                .nonNulls
                                .firstOrNull;
                            if (code != null && !circle.loading) _find(code);
                          },
                          errorBuilder: (context, error) => ColoredBox(
                            color: pop.stage,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                    "The camera isn't available. Type the code "
                                    'under their QR instead.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: pop.haze)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ))),
            const SizedBox(height: 10),
            Text('Point at the QR on their Circle tab',
                textAlign: TextAlign.center, style: TextStyle(color: pop.haze)),
            const SizedBox(height: 20),
            TextField(
              controller: _field,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              style: FloorPop.readout(22),
              decoration: InputDecoration(
                labelText: 'Or type the code',
                hintText: 'SHGY-7FK2',
                errorText: circle.error.isEmpty ? null : circle.error,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () async {
                    final text = (await Clipboard.getData('text/plain'))?.text;
                    if (text == null) return;
                    final code = findCircleCode(text);
                    _field.text = code == null ? text : formatCircleCode(code);
                    setState(() {});
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => typed == null ? null : _find(typed),
            ),
            const SizedBox(height: 16),
            VoltButton(
              onPressed:
                  typed != null && !circle.loading ? () => _find(typed) : null,
              child: const Text('Find circle', style: _bold),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(children: [
              CircleBubble(preview.leader, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${preview.leader.name}'s circle",
                          style: FloorPop.display(18,
                              color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(
                          'DDR-CODE ${formatDdrCode(preview.leader.ddrCode)} · '
                          '${preview.members} in it',
                          style: TextStyle(color: pop.haze)),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            Text(
                "Joining means you cheer for ${preview.leader.name}. They'll "
                'see your dancer name and DDR-CODE.',
                style: TextStyle(color: pop.haze, height: 1.4)),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _back,
              onChanged: (on) => setState(() => _back = on!),
              title: Text('Let ${preview.leader.name} cheer for me too'),
              subtitle: const Text("Then you're friends straight away"),
            ),
            if (circle.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(circle.error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 20),
            VoltButton(
              onPressed: circle.loading ? null : _join,
              child:
                  Text(_back ? 'Become friends' : 'Join circle', style: _bold),
            ),
            TextButton(
              onPressed: () {
                setState(() => _preview = null);
                _scanner.start();
              },
              child: const Text('Not this one'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Just joined [leader]'s circle: friends if they were already in yours,
/// else the other half, them scanning your QR, one tap away.
class _Joined extends StatelessWidget {
  const _Joined(this.leader, {required this.friends});
  final CirclePerson leader;
  final bool friends;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CircleArt(friends ? CircleScene.friends : CircleScene.theyScan),
      const SizedBox(height: 12),
      Text(
          friends
              ? 'You and ${leader.name} are friends'
              : 'You cheer for ${leader.name}',
          textAlign: TextAlign.center,
          style: FloorPop.display(20,
              color: Theme.of(context).colorScheme.onSurface)),
      const SizedBox(height: 8),
      Text(
          friends
              ? "You're in each other's circles."
              : 'Halfway there. Let ${leader.name} scan your QR so they cheer '
                  "for you too, and you're friends.",
          textAlign: TextAlign.center,
          style: TextStyle(color: pop.haze, height: 1.45)),
      const SizedBox(height: 24),
      if (!friends)
        VoltButton(
          onPressed: () => showInviteSheet(context),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.qr_code_2, size: 20),
            SizedBox(width: 8),
            Text('Show my QR', style: _bold),
          ]),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(friends ? 'Done' : 'Later'),
      ),
    ]);
  }
}

/// How you and someone are tied: in each other's circles, or one way.
/// Its [icon] points the way the cheering goes: both ways, out, in.
enum CircleTie {
  friends(Icons.sync_alt, 'Friends', "You're in each other's circles"),
  youCheer(Icons.arrow_outward, 'You cheer for',
      "You cheer for them; they haven't scanned your QR"),
  cheeringYou(Icons.call_received, 'Cheering you on',
      "Cheering you on; you haven't scanned their QR");

  const CircleTie(this.icon, this.heading, this.description);
  final IconData icon;
  final String heading;
  final String description;
}

/// [person] and how you're tied, with leaving their circle when you're in
/// it and taking them out of yours when they're in it.
Future<void> showPersonSheet(
    BuildContext context, CirclePerson person, CircleTie tie) {
  final circle = context.read<CircleState>();
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleBubble(person, size: 64),
        const SizedBox(height: 10),
        Text(person.name,
            style: FloorPop.display(18,
                color: Theme.of(sheet).colorScheme.onSurface)),
        Text('DDR-CODE ${formatDdrCode(person.ddrCode)}',
            style: TextStyle(color: FloorPop.of(sheet).haze)),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(tie.icon, size: 14, color: FloorPop.of(sheet).voltText),
          const SizedBox(width: 6),
          Text(tie.description,
              style: TextStyle(color: FloorPop.of(sheet).haze, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        if (tie != CircleTie.cheeringYou)
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text("Leave ${person.name}'s circle"),
            onTap: () {
              Navigator.pop(sheet);
              circle.leave(person);
            },
          ),
        if (tie != CircleTie.youCheer)
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('Take out of your circle'),
            onTap: () {
              Navigator.pop(sheet);
              circle.remove(person);
            },
          ),
      ]),
    ),
  );
}

/// Your dancer name and DDR-CODE, and deleting everything circles holds
/// about you.
Future<void> showCircleSettings(BuildContext context) {
  final circle = context.read<CircleState>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(sheet).bottom + 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleProfileForm(onSaved: () => Navigator.pop(sheet)),
            const SizedBox(height: 16),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(sheet).colorScheme.error),
              onPressed: () async {
                if (await confirmDelete(
                    sheet,
                    'Leave circles and delete?',
                    "Your profile, your circle and every circle you're in "
                        'are deleted from the server. People in your circle '
                        'lose you.')) {
                  await circle.deleteAll();
                  if (sheet.mounted) Navigator.pop(sheet);
                }
              },
              child: const Text('Leave circles & delete'),
            ),
          ],
        ),
      ),
    ),
  );
}
