/// Name: EamuseSyncCard
/// Parent: SessionPage
/// Description: Home's e-amusement row: when it last synced, with one button
/// to sync now (or stop, or sign in on Konami's own page first) and a bar
/// along the bottom while it runs.
/// Signing out and the auto-sync choice live in Settings.
library;

import 'package:ddr_md/helpers.dart';
import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

/// Syncs e-amusement, signing in on Konami's page first when signed out.
Future<void> signInAndSync(BuildContext context) async {
  final state = context.read<EamuseSyncState>();
  if (state.status != EamuseStatus.signedOut) return state.sync(asked: true);
  // Over the whole app, tab bar included, sliding up like a system browser.
  final signedIn = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
          fullscreenDialog: true, builder: (_) => const _EamuseSignInPage()));
  if (signedIn == true) await state.sync(renewed: true);
}

class EamuseSyncCard extends StatelessWidget {
  const EamuseSyncCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EamuseSyncState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = state.syncedAt;
    final (status, detail) = switch (state.status) {
      EamuseStatus.signedOut => ('Not signed in', ''),
      EamuseStatus.syncing => (
          'Syncing · ${(state.progress * 100).round()}%',
          state.note
        ),
      EamuseStatus.failed => (state.error, ''),
      EamuseStatus.idle when at == null => ('Not synced yet', ''),
      EamuseStatus.idle => (
          [
            'Synced ${formatAgo(at!)}',
            if (state.changed case final n? when n > 0) '$n updated',
            if (state.cards case final n? when n > 0)
              '$n ${n == 1 ? 'card' : 'cards'}',
          ].join(' · '),
          ''
        ),
    };
    final button = switch (state.status) {
      EamuseStatus.signedOut => FilledButton(
          onPressed: () => signInAndSync(context),
          child: const Text('Sign in')),
      EamuseStatus.syncing =>
        TextButton(onPressed: state.stop, child: const Text('Stop')),
      EamuseStatus.failed => FilledButton.tonal(
          onPressed: state.refused ? null : () => state.sync(asked: true),
          child: const Text('Retry')),
      _ => FilledButton.tonalIcon(
          onPressed: state.refused ? null : () => state.sync(asked: true),
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('Sync')),
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Icon(Icons.cloud_sync_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('e-amusement',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: state.status == EamuseStatus.failed
                              ? scheme.error
                              : null)),
                  if (detail.isNotEmpty)
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            button,
          ]),
        ),
        // The running sync along the card's foot; the same height idle, so
        // the card doesn't jump.
        SizedBox(
          height: 3,
          child: state.status == EamuseStatus.syncing
              ? LinearProgressIndicator(
                  value: state.progress == 0 ? null : state.progress,
                  minHeight: 3)
              : null,
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
