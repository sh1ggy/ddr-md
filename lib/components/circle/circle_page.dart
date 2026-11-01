/// Name: CirclePage
/// Parent: Router
/// Description: The Circle tab, people grouped by how you're tied: friends
/// (in each other's circles) as bubbles, then the one-way ties, those you
/// cheer for and those cheering you on, each with what makes it two-way.
/// The header holds your invite QR, scanning someone's, and your name and
/// DDR-CODE. Before joining circles there's only the form for your name and
/// code, filled from e-amusement when linked.
library;

import 'package:ddr_md/components/circle/circle_explainer.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/nav_bar.dart' show LivePulse;
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CirclePage extends StatefulWidget {
  const CirclePage({super.key});

  @override
  State<CirclePage> createState() => _CirclePageState();
}

class _CirclePageState extends State<CirclePage> {
  // Until the first answer, as a profile may already be on the server
  // (made with this key elsewhere) though none is kept here.
  bool _checking = CircleState.available;
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final circle = context.read<CircleState>();
    // Back in the app, what changed meanwhile (someone joining) shows.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (circle.id != null) circle.refresh();
    });
    if (!_checking) return;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => circle.refresh().whenComplete(() {
              if (mounted) setState(() => _checking = false);
            }));
  }

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final ready = CircleState.available && circle.id != null;
    // Whoever's on the pad now comes first.
    final following = [...circle.following]
      ..sort((a, b) => (b.live == null ? 0 : 1) - (a.live == null ? 0 : 1));
    final friends = [
      for (final p in following)
        if (p.friend) p
    ];
    final youCheer = [
      for (final p in following)
        if (!p.friend) p
    ];
    final cheeringYou = [
      for (final p in circle.circle)
        if (!p.friend) p
    ];
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const PageTitle('Circle'),
        actions: [
          if (ready) ...[
            HeaderButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'How circles work',
              onPressed: () => showCircleExplainer(context),
            ),
            HeaderButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: 'Scan each other',
              onPressed: () => showInviteSheet(context),
            ),
            HeaderButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Circle settings',
              onPressed: () => showCircleSettings(context),
            ),
          ],
          const SizedBox(width: 12),
        ],
      ),
      body: !CircleState.available
          ? const _Message("Circles aren't switched on in this build.")
          : !ready
              ? _checking && circle.id == null
                  ? const Center(child: CircularProgressIndicator())
                  : const CircleProfileForm()
              : RefreshIndicator(
                  edgeOffset: MediaQuery.paddingOf(context).top + 56,
                  onRefresh: circle.refresh,
                  child: ListView(
                    padding: clearOfBars(
                        context, const EdgeInsets.fromLTRB(16, 64, 16, 120)),
                    children: [
                      if (circle.error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(circle.error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      if (friends.isEmpty &&
                          youCheer.isEmpty &&
                          cheeringYou.isEmpty)
                        const _Empty()
                      else ...[
                        if (friends.isNotEmpty) ...[
                          _Heading(CircleTie.friends, friends.length),
                          _FriendBubbles(friends),
                        ],
                        if (youCheer.isNotEmpty) ...[
                          _Heading(CircleTie.youCheer, youCheer.length),
                          for (final p in youCheer)
                            _PersonTile(p, CircleTie.youCheer),
                        ],
                        if (cheeringYou.isNotEmpty) ...[
                          _Heading(CircleTie.cheeringYou, cheeringYou.length),
                          for (final p in cheeringYou)
                            _PersonTile(p, CircleTie.cheeringYou),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: FloorPop.of(context).haze)),
        ),
      );
}

/// A group's heading, led by its tie's arrow.
class _Heading extends StatelessWidget {
  const _Heading(this.tie, this.count);
  final CircleTie tie;
  final int count;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 26, 0, 10),
      child: Row(children: [
        Icon(tie.icon, size: 15, color: pop.voltText),
        const SizedBox(width: 6),
        Text('${tie.heading.toUpperCase()} · $count', style: pop.label),
      ]),
    );
  }
}

/// No ties yet: the friends drawing, the idea, and the two ways in.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CircleArt(CircleScene.friends),
        const SizedBox(height: 12),
        Text('Scan each other',
            textAlign: TextAlign.center,
            style: FloorPop.display(20,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 8),
        Text(
            "Scan a friend's QR, or have them scan yours. One scan and you're "
            'friends, cheering each other on.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pop.haze, height: 1.45)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showInviteSheet(context),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Show my QR'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => openJoinCircle(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan theirs'),
            ),
          ),
        ]),
        TextButton(
          onPressed: () => showCircleExplainer(context),
          child: const Text('How it works'),
        ),
      ]),
    );
  }
}

/// A player's bubble: their name's first letter on a colour of its own.
class CircleBubble extends StatelessWidget {
  const CircleBubble(this.person, {super.key, this.size = 58});

  final CirclePerson person;
  final double size;

  // Never Volt, which on this tab means live.
  static const _colors = [
    FloorPop.coral,
    FloorPop.padBlue,
    FloorPop.sun,
    FloorPop.grape,
  ];

  @override
  Widget build(BuildContext context) {
    final color =
        _colors[person.id.codeUnits.fold(0, (a, b) => a + b) % _colors.length];
    final dark = color == FloorPop.padBlue || color == FloorPop.grape;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(person.name.isEmpty ? '?' : person.name.substring(0, 1),
          style: FloorPop.display(size * 0.34,
              color: dark ? Colors.white : FloorPop.onVolt)),
    );
  }
}

class _FriendBubbles extends StatelessWidget {
  const _FriendBubbles(this.friends);
  final List<CirclePerson> friends;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(children: [
          for (final p in friends)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showPersonSheet(context, p, CircleTie.friends),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    CircleBubble(p, size: 64),
                    if (p.live != null)
                      const Positioned(
                          left: 0, right: 0, bottom: -6, child: _LiveTag()),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 72,
                    child: Text(p.name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  if (p.live case final live?)
                    SizedBox(
                      width: 72,
                      child: Text(_liveLine(live),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: FloorPop.of(context).voltText)),
                    ),
                ]),
              ),
            ),
        ]),
      );
}

/// Where someone live is: "C2 · Garden City".
String _liveLine(CircleLive live) =>
    [if (live.credit > 0) 'C${live.credit}', live.venue].join(' · ');

/// Volt LIVE over a bubble whose player is on the pad.
class _LiveTag extends StatelessWidget {
  const _LiveTag();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
          decoration: BoxDecoration(
              color: FloorPop.volt, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const LivePulse(color: FloorPop.onVolt),
            const SizedBox(width: 4),
            Text('LIVE',
                style: FloorPop.readout(10, color: FloorPop.onVolt)
                    .copyWith(letterSpacing: 0.8)),
          ]),
        ),
      );
}

/// A one-way tie, with the step that would make it two-way.
class _PersonTile extends StatelessWidget {
  const _PersonTile(this.person, this.tie);
  final CirclePerson person;
  final CircleTie tie;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final youCheer = tie == CircleTie.youCheer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: pop.stage,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: pop.line)),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          leading: CircleBubble(person, size: 40),
          title: Text(person.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: switch (person.live) {
            final live? => Text('LIVE · ${_liveLine(live)}',
                style: TextStyle(color: pop.voltText)),
            null => Text(formatDdrCode(person.ddrCode)),
          },
          onTap: () => showPersonSheet(context, person, tie),
          trailing: TextButton.icon(
            onPressed: () =>
                youCheer ? showInviteSheet(context) : openJoinCircle(context),
            icon: Icon(youCheer ? Icons.qr_code_2 : Icons.qr_code_scanner,
                size: 18),
            label: Text(youCheer ? 'Show your QR' : 'Scan theirs'),
          ),
        ),
      ),
    );
  }
}

/// Your dancer name and DDR-CODE, as others in circles see them: filled
/// from e-amusement when it's linked. First run shows it as the whole tab;
/// the settings sheet reuses it to change either.
class CircleProfileForm extends StatefulWidget {
  const CircleProfileForm({super.key, this.onSaved});

  /// After a later save; first run has the tab rebuild instead.
  final VoidCallback? onSaved;

  @override
  State<CircleProfileForm> createState() => _CircleProfileFormState();
}

class _CircleProfileFormState extends State<CircleProfileForm> {
  late final _name = TextEditingController();
  late final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    final circle = context.read<CircleState>();
    _name.text = circle.name.isNotEmpty
        ? circle.name
        : Settings.getString(Settings.eamuseNameKey).toUpperCase();
    _code.text = formatDdrCode(circle.ddrCode.isNotEmpty
        ? circle.ddrCode
        : Settings.getString(Settings.rivalCodeSpeedKey)
            .replaceAll(RegExp(r'\D'), ''));
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _digits => _code.text.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final pop = FloorPop.of(context);
    final first = widget.onSaved == null;
    final valid = CircleState.namePattern.hasMatch(_name.text.trim()) &&
        _digits.length == 8;
    final form = [
      TextField(
        controller: _name,
        autocorrect: false,
        maxLength: 8,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Dancer name'),
        onChanged: (text) {
          final upper = text.toUpperCase();
          if (upper != text) _name.value = _name.value.copyWith(text: upper);
          setState(() {});
        },
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'DDR-CODE',
          hintText: '1234-5678',
          errorText: circle.error.isEmpty ? null : circle.error,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 16),
      VoltButton(
        onPressed: valid && !circle.loading
            ? () async {
                if (!await circle.claim(_name.text.trim(), _digits)) return;
                widget.onSaved?.call();
                // A circle just started: how it works, once.
                if (first && context.mounted) showCircleExplainer(context);
              }
            : null,
        child: Text(
            circle.loading
                ? 'Saving…'
                : first
                    ? 'Start my circle'
                    : 'Save',
            style: const TextStyle(
                fontFamily: kTextFont,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    ];
    if (!first) {
      return Column(mainAxisSize: MainAxisSize.min, children: form);
    }
    return ListView(
      padding: clearOfBars(context, const EdgeInsets.fromLTRB(20, 72, 20, 120)),
      children: [
        Text('Your cheer squad',
            style: FloorPop.display(22,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 10),
        Text(
            'Friends scan your QR to join your circle, follow your sessions '
            "and cheer you on. Scan theirs and you're friends.\n\n"
            'They see you by your dancer name and DDR-CODE. Nothing else '
            'about you is shared unless you choose to.',
            style: TextStyle(color: pop.haze, height: 1.45)),
        const SizedBox(height: 24),
        ...form,
      ],
    );
  }
}
