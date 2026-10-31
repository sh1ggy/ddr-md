/// Name: EamuseSyncCard
/// Parent: SessionPage
/// Description: Home's e-amusement row: sync status, a round sync button
/// ringed by the running sync's progress from [EamuseSyncState], and sign
/// out. Signs in on Konami's own page first when needed.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

class EamuseSyncCard extends StatelessWidget {
  const EamuseSyncCard({super.key});

  Future<void> _signInAndSync(BuildContext context) async {
    final state = context.read<EamuseSyncState>();
    // Over the whole app, tab bar included, sliding up like a system browser.
    final signedIn = await Navigator.of(context, rootNavigator: true)
        .push<bool>(MaterialPageRoute(
            fullscreenDialog: true, builder: (_) => const _EamuseSignInPage()));
    if (signedIn == true) state.sync(renewed: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EamuseSyncState>();
    final theme = Theme.of(context);
    final syncing = state.status == EamuseStatus.syncing;
    if (state.status == EamuseStatus.signedOut) {
      return _SignedOutRow(onSignIn: () => _signInAndSync(context));
    }
    final at = state.syncedAt;
    final status = switch (state.status) {
      EamuseStatus.syncing => 'Syncing ${(state.progress * 100).round()}%',
      EamuseStatus.signedOut => 'Signed out',
      EamuseStatus.failed => state.error,
      EamuseStatus.idle when at != null => [
          '${state.charts} charts',
          if (state.changed != null)
            state.changed == 0 ? 'no changes' : '${state.changed} updated',
          if (state.cards case final n? when n > 0)
            '$n ${n == 1 ? 'card' : 'cards'} collected',
          formatDate(at),
        ].join(' · '),
      EamuseStatus.idle => 'Not synced yet',
    };
    final scheme = theme.colorScheme;
    return _AccountRow(
      lines: [
        Text(status,
            style: theme.textTheme.bodySmall?.copyWith(
                color: state.status == EamuseStatus.failed
                    ? scheme.error
                    : scheme.onSurfaceVariant)),
        if (state.note.isNotEmpty)
          Text(state.note,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
      trailing: [
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout, size: 20),
          color: scheme.onSurfaceVariant,
          onPressed: syncing ? null : () => _confirmSignOut(context, state),
        ),
        const SizedBox(width: 4),
        _SyncButton(state),
      ],
    );
  }

  Future<void> _confirmSignOut(
      BuildContext context, EamuseSyncState state) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of e-amusement?'),
        content: const Text('Your synced scores stay on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (yes == true) await state.signOut();
  }
}

/// The card signed out, with a sign-in button.
class _SignedOutRow extends StatelessWidget {
  const _SignedOutRow({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _AccountRow(
      lines: [
        Text('Not signed in',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
      trailing: [
        // Same round button in the same place as sync once signed in.
        SizedBox.square(
          dimension: 48,
          child: Center(
            child: IconButton.filled(
              tooltip: 'Sign in',
              icon: const Icon(Icons.login),
              onPressed: onSignIn,
            ),
          ),
        ),
      ],
    );
  }
}

/// The card's one row: the icon, the title over its status lines, then
/// actions.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.lines, required this.trailing});

  final List<Widget> lines;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(children: [
          // Centred on the title and status together.
          Icon(Icons.cloud_sync_outlined,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('e-amusement',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ...lines,
              ],
            ),
          ),
          const SizedBox(width: 8),
          ...trailing,
        ]),
      ),
    );
  }
}

/// A round sync button. While syncing, a ring around it fills to the
/// progress and it stops the sync.
class _SyncButton extends StatelessWidget {
  const _SyncButton(this.state);

  final EamuseSyncState state;

  @override
  Widget build(BuildContext context) {
    final syncing = state.status == EamuseStatus.syncing;
    return SizedBox.square(
      dimension: 48,
      child: Stack(alignment: Alignment.center, children: [
        if (syncing)
          SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(
              value: state.progress,
              strokeWidth: 3,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        syncing
            ? IconButton.filledTonal(
                tooltip: 'Stop syncing',
                icon: const Icon(Icons.stop),
                onPressed: state.stop,
              )
            : IconButton.filled(
                tooltip: state.upToDate
                    ? 'Up to date'
                    : state.waiting
                        ? 'Sync again shortly'
                        : 'Sync scores',
                icon: Icon(state.upToDate ? Icons.check : Icons.sync),
                onPressed: state.upToDate || state.waiting ? null : state.sync,
              ),
      ]),
    );
  }
}

/// Konami's sign-in page in an in-app browser: the page's title over its
/// host, a load bar, reload and back through its history. Pops true once it
/// lands on the play data pages.
class _EamuseSignInPage extends StatefulWidget {
  const _EamuseSignInPage();

  @override
  State<_EamuseSignInPage> createState() => _EamuseSignInPageState();
}

class _EamuseSignInPageState extends State<_EamuseSignInPage> {
  InAppWebViewController? _web;
  WebUri _url = WebUri(kEamuseLoginUrl);
  String _title = '';
  double _progress = 0;
  bool _canGoBack = false;
  String? _error;
  // Landing is seen by both the load and the history callbacks; pop once.
  bool _done = false;

  void _visited(WebUri? url) async {
    if (url == null || _done) return;
    if (url.host == Uri.parse(kEamuseHost).host &&
        url.path.startsWith(kEamusePlayDataPath)) {
      _done = true;
      Navigator.of(context).pop(true);
      return;
    }
    final back = await _web?.canGoBack() ?? false;
    if (mounted) {
      setState(() {
        _url = url;
        _canGoBack = back;
      });
    }
  }

  void _reload() {
    setState(() => _error = null);
    _web?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.2);
    return PopScope(
      // Back steps through the page's history before leaving it.
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _web?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title.isEmpty ? 'Sign in to e-amusement' : _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Row(children: [
                Icon(_url.scheme == 'https' ? Icons.lock : Icons.lock_open,
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(_url.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted),
                ),
              ]),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress < 1
                ? LinearProgressIndicator(value: _progress, minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
        body: Stack(children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: _url),
            initialSettings: InAppWebViewSettings(
              allowsBackForwardNavigationGestures: true,
              transparentBackground: true,
            ),
            onWebViewCreated: (controller) => _web = controller,
            onLoadStart: (_, url) => setState(() => _error = null),
            onLoadStop: (_, url) => _visited(url),
            onUpdateVisitedHistory: (_, url, __) => _visited(url),
            onTitleChanged: (_, title) =>
                setState(() => _title = title?.trim() ?? ''),
            onProgressChanged: (_, progress) =>
                setState(() => _progress = progress / 100),
            onReceivedError: (_, request, error) {
              // A redirect or a superseded load cancels the one before it.
              if (request.isForMainFrame == false ||
                  error.type == WebResourceErrorType.CANCELLED) {
                return;
              }
              setState(() => _error = error.description);
            },
          ),
          if (_error case final error?)
            Positioned.fill(
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off,
                          size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text("Couldn't load the sign-in page",
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(error, textAlign: TextAlign.center, style: muted),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                          onPressed: _reload, child: const Text('Try again')),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
