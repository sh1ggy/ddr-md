/// Name: SettingsPage
/// Parent: Main
/// Description: Profile tab: e-amusement profile, statistics and play
/// preferences, persisted with shared_preferences
library;

import 'package:ddr_md/components/settings/dancer_type_page.dart';
import 'package:ddr_md/components/settings/eamuse_profile_card.dart';
import 'package:ddr_md/components/settings/footing_style_page.dart';
import 'package:ddr_md/components/settings/score_overview_page.dart';
import 'package:ddr_md/components/song_json.dart';
import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/settings_model.dart';
import 'package:ddr_md/models/song_model.dart';
import 'package:ddr_md/components/floor_pop_widgets.dart';
import 'package:ddr_md/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _chosenReadSpeed = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  /// Load the initial counter value from persistent storage on start,
  /// or fallback to constant BPM value if it doesn't exist.
  Future<void> _loadPrefs() async {
    setState(() {
      _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    });
  }

  /// After setting BPM preference, asynchronously save it
  /// to persistent storage.
  void _setReadSpeed(int newValue) {
    setState(() {
      Settings.setInt(Settings.chosenReadSpeedKey, newValue);
      _chosenReadSpeed = Settings.getInt(Settings.chosenReadSpeedKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              appBar: AppBar(
                title: const Text('Profile'),
              ),
              body: Stack(
                children: [
                  ListView(
                    padding: clearOfTabBar(context, const EdgeInsets.all(8)),
                    children: [
                      const _SectionHeader('Profile', Icons.person),
                      const EamuseProfileCard(),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.leaderboard_outlined),
                          title: const Text("Statistics",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ScoreOverviewPage())),
                        ),
                      ),
                      _ReadSpeedCard(
                        value: _chosenReadSpeed,
                        onChanged: _setReadSpeed,
                      ),
                      const _SectionHeader('Dancer', Icons.accessibility_new),
                      Card(
                        child: ListTile(
                          title: const Text("Dancer Type",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle:
                              const Text("Height, shoe size and bar grip"),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const DancerTypePage())),
                        ),
                      ),
                      const _SectionHeader('Play', Icons.directions_run),
                      const _PlayStyleCard(),
                      Card(
                        child: ListTile(
                          title: const Text("Footing Style",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FootingStyleSwitch(
                                  onChanged: () => setState(() {})),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const FootingStylePage()));
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}

/// Play style (singles/doubles) selector, persisted via [SongState.setMode].
class _PlayStyleCard extends StatelessWidget {
  const _PlayStyleCard();

  @override
  Widget build(BuildContext context) {
    var songState = context.watch<SongState>();
    ButtonSegment<Modes> segment(Modes mode, String asset) => ButtonSegment(
        value: mode,
        label: Opacity(
          opacity: songState.modes == mode ? 1 : 0.4,
          child: Image.asset(asset, height: 15),
        ));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<Modes>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            segment(Modes.singles, 'assets/icons/style_single.png'),
            segment(Modes.doubles, 'assets/icons/style_double.png'),
          ],
          selected: {songState.modes},
          onSelectionChanged: (s) {
            songState.setMode(s.first);
            showToast(context,
                "Set play style to ${s.first == Modes.singles ? "singles" : "doubles"}");
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 6),
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: Colors.blueGrey,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The read speed hi-speed suggestions aim for: −10 and +10 either side of
/// it, and the number itself takes a typed value.
class _ReadSpeedCard extends StatefulWidget {
  const _ReadSpeedCard({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_ReadSpeedCard> createState() => _ReadSpeedCardState();
}

class _ReadSpeedCardState extends State<_ReadSpeedCard> {
  static const _min = 100, _max = 999, _step = 10;
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_ReadSpeedCard old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(int value) {
    final clamped = value.clamp(_min, _max);
    _controller.text = '$clamped';
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  // A typed value lands when the field lets go; out of range it snaps in.
  void _commit() {
    final typed = int.tryParse(_controller.text);
    _set(typed ?? widget.value);
  }

  void _nudge(int by) {
    HapticFeedback.selectionClick();
    _set(widget.value + by);
  }

  @override
  Widget build(BuildContext context) {
    final pop = FloorPop.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget nudge(String label, int by, String tooltip) => IconButton(
          tooltip: tooltip,
          onPressed: (widget.value + by).clamp(_min, _max) == widget.value
              ? null
              : () => _nudge(by),
          style: IconButton.styleFrom(
            backgroundColor: pop.riser,
            foregroundColor: scheme.onSurface,
            fixedSize: const Size(44, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Text(label,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Read speed',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 2),
                Text('Hi-speed suggestions aim for this',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          nudge('−', -_step, 'Read speed down $_step'),
          SizedBox(
            width: 70,
            child: Semantics(
              label: 'Read speed',
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                onSubmitted: (_) => _commit(),
                style: FloorPop.readout(26, color: pop.voltText),
                decoration: const InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          nudge('+', _step, 'Read speed up $_step'),
        ]),
      ),
    );
  }
}
