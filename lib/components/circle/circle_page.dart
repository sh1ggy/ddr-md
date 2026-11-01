/// Name: CirclePage
/// Parent: Router
/// Description: The Circle tab, people grouped by how you're tied: friends
/// (in each other's circles) as bubbles, then the latest finished session
/// of each you follow to cheer, then the one-way ties, those you cheer for
/// and those cheering you on. The header holds Invite and the settings;
/// scanning sits above the tab bar.
/// Before joining circles there's the idea, your name and code from
/// e-amusement and the button that starts your circle; while nobody's in it
/// yet, scanning and your QR wait together at the bottom.
library;

import 'dart:async';

import 'package:ddr_md/components/circle/circle_credit_card.dart';
import 'package:ddr_md/components/circle/circle_art.dart';
import 'package:ddr_md/components/circle/circle_person_page.dart';
import 'package:ddr_md/components/circle/circle_sheets.dart';
import 'package:ddr_md/components/circle/circle_widgets.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/components/session/eamuse_sync_card.dart'
    show signInAndSync;
import 'package:ddr_md/components/nav_bar.dart' show LivePulse;
import 'package:ddr_md/models/circle_model.dart';
import 'package:ddr_md/models/eamuse_state.dart';
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
  late final Timer _poll;

  @override
  void dispose() {
    _lifecycle.dispose();
    _poll.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final circle = context.read<CircleState>();
    // Back in the app, what changed meanwhile (someone joining) shows.
    _lifecycle = AppLifecycleListener(onResume: () {
      if (circle.id != null) circle.poll();
    });
    // Someone you follow on the pad: their credits and credit number keep
    // up while this tab's on screen, not while another tab is.
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          circle.following.any((p) => p.live != null)) {
        circle.poll();
      }
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
    // Sessions that are over, the latest first; a live one is on its page.
    final latest = [
      for (final p in following)
        if (p.live == null)
          if (circle.lastSessionOf(p) case final s when s.isNotEmpty) s
    ]..sort((a, b) => b.first.at.compareTo(a.first.at));
    final empty = friends.isEmpty && youCheer.isEmpty && cheeringYou.isEmpty;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        flexibleSpace: const GlassHeader(),
        title: const PageTitle('Circle'),
        actions: [
          if (ready) ...[
            // While it's empty the tab's own buttons invite.
            if (!empty)
              SizedBox(
                width: 96,
                child: VoltButton(
                  height: 40,
                  radius: 14,
                  onPressed: () => showInviteSheet(context),
                  child: const Text('Invite', style: _bold),
                ),
              ),
            HeaderButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Circle settings',
              onPressed: () => showCircleSettings(context),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: !CircleState.available
          ? const _Message("Circles aren't switched on in this build.")
          : !ready
              ? _checking && circle.id == null
                  ? const Center(child: CircularProgressIndicator())
                  : const _FirstRun()
              : _WithActions(
                  actions: empty
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(
                                child: GhostButton(
                                  height: 56,
                                  onPressed: () => openJoinCircle(context),
                                  icon: const Icon(Icons.qr_code_scanner,
                                      size: 20),
                                  child: const Text('Scan theirs'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: VoltButton(
                                  onPressed: () => showInviteSheet(context),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.qr_code_2, size: 20),
                                        SizedBox(width: 8),
                                        Text('Show my QR', style: _bold),
                                      ]),
                                ),
                              ),
                            ])
                      : CircleScanButton(
                          onPressed: () => openJoinCircle(context)),
                  child: RefreshIndicator(
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
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ),
                        if (empty)
                          const _Hero(
                              title: 'Scan each other',
                              line: "Scan a friend's QR or have them scan "
                                  "yours. One scan and you're friends.")
                        else ...[
                          if (friends.isNotEmpty) ...[
                            _Heading(CircleTie.friends, friends.length),
                            _FriendBubbles(friends),
                          ],
                          if (latest.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 26, 0, 10),
                              child: Text('LATEST',
                                  style: FloorPop.of(context).label),
                            ),
                            for (final s in latest)
                              CircleSessionCard(s, header: true),
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
                ),
    );
  }
}

const _bold =
    TextStyle(fontFamily: kTextFont, fontSize: 15, fontWeight: FontWeight.w700);

/// [child] with [actions], when there are any, pinned above the tab bar
/// where a thumb reaches them.
class _WithActions extends StatelessWidget {
  const _WithActions({required this.child, this.actions});
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: child),
        if (actions != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: actions!,
          ),
      ]);
}

/// The drawing, a headline and one line: what the tab is for.
class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.line});
  final String title, line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(children: [
          const CircleArt(CircleScene.friends),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: FloorPop.display(22,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 8),
          Text(line,
              textAlign: TextAlign.center,
              style: TextStyle(color: FloorPop.of(context).haze, height: 1.45)),
        ]),
      );
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
              onTap: () => openPersonPage(context, p, CircleTie.friends),
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

/// A one-way tie: who, and where they're playing when live.
class _PersonTile extends StatelessWidget {
  const _PersonTile(this.person, this.tie);
  final CirclePerson person;
  final CircleTie tie;

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
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
            null => Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: DdrCodeBadge(person.ddrCode),
                )),
          },
          onTap: () => openPersonPage(context, person, tie),
          trailing: Icon(Icons.chevron_right, color: pop.haze),
        ),
      ),
    );
  }
}

/// Before a circle: the idea in a line, who you'll be to others (your
/// dancer name and rival code from e-amusement, never typed) and one button,
/// which syncs e-amusement first if it hasn't yet, then starts the circle
/// and shows your QR, the next thing you'll want with a friend beside you.
class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    final sync = context.watch<EamuseSyncState>();
    final pop = FloorPop.of(context);
    final (name, code) = konamiIdentity();
    final valid = CircleState.namePattern.hasMatch(name) && code.length == 8;
    final syncing = sync.status == EamuseStatus.syncing;
    return _WithActions(
      actions: VoltButton(
        onPressed: circle.loading || syncing
            ? null
            : valid
                ? () async {
                    if (await circle.claimKonamiProfile() && context.mounted) {
                      showInviteSheet(context);
                    }
                  }
                : () => signInAndSync(context),
        child: Text(
            syncing
                ? 'Syncing ${(sync.progress * 100).round()}%'
                : circle.loading
                    ? 'Starting…'
                    : valid
                        ? 'Start my circle'
                        : 'Sync e-amusement',
            style: _bold),
      ),
      child: ListView(
        padding:
            clearOfBars(context, const EdgeInsets.fromLTRB(20, 64, 20, 120)),
        children: [
          const _Hero(
              title: 'Cheer each other on',
              line: "Scan a friend's QR and you're friends: see when they're "
                  'on the pad and cheer their credits.'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: pop.stage,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: pop.line)),
            child: valid
                ? Row(children: [
                    CircleBubble((
                      id: code,
                      name: name,
                      ddrCode: code,
                      friend: false,
                      live: null
                    ), size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 6),
                            DdrCodeBadge(code),
                          ]),
                    ),
                    Icon(Icons.lock_outline, size: 18, color: pop.haze),
                  ])
                : Text(
                    sync.status == EamuseStatus.failed
                        ? sync.error
                        : 'Sync e-amusement and friends see you by your '
                            'dancer name and rival code.',
                    style: TextStyle(color: pop.haze, height: 1.4)),
          ),
          const SizedBox(height: 10),
          Text(
              valid
                  ? 'How friends see you, from e-amusement. Nothing else is '
                      'shared unless you choose to.'
                  : 'Nothing else is shared unless you choose to.',
              style: TextStyle(color: pop.haze, fontSize: 12, height: 1.4)),
          if (circle.error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(circle.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

/// The dancer name and digits-only rival code from the last e-amusement
/// sync, as circles shows them.
(String, String) konamiIdentity() => (
      Settings.getString(Settings.eamuseNameKey).trim().toUpperCase(),
      Settings.getString(Settings.rivalCodeSpeedKey)
          .replaceAll(RegExp(r'\D'), ''),
    );

/// Your dancer name and DDR-CODE, as others in circles see them, read-only
/// in the settings sheet: from e-amusement, never typed.
class CircleProfileForm extends StatelessWidget {
  const CircleProfileForm({super.key});

  @override
  Widget build(BuildContext context) {
    final circle = context.watch<CircleState>();
    // Profile values update after the next successful e-amusement sync.
    context.select<EamuseSyncState, int>((sync) => sync.revision);
    final pop = FloorPop.of(context);
    final (name, code) = konamiIdentity();
    final hasProfile = name.isNotEmpty && code.length == 8;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _KonamiIdentity(label: 'Dancer name', value: name, available: hasProfile),
      const SizedBox(height: 8),
      if (hasProfile)
        Align(alignment: Alignment.centerLeft, child: DdrCodeBadge(code))
      else ...[
        const _KonamiIdentity(label: 'Rival code', value: '', available: false),
        const SizedBox(height: 8),
        Text('Sync e-amusement from Home to load your Konami profile.',
            style: TextStyle(color: pop.haze, height: 1.4)),
      ],
      if (circle.error.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(circle.error,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ]);
  }
}

/// A read-only value supplied by the player's latest e-amusement profile.
class _KonamiIdentity extends StatelessWidget {
  const _KonamiIdentity(
      {required this.label, required this.value, required this.available});

  final String label;
  final String value;
  final bool available;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.lock_outline, size: 18),
        ),
        child: Text(
          available ? value : 'Not synced',
          style: TextStyle(
              color: available
                  ? Theme.of(context).colorScheme.onSurface
                  : FloorPop.of(context).haze),
        ),
      );
}
