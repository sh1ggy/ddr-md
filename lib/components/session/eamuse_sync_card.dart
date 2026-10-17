/// Name: EamuseSyncCard
/// Parent: SessionPage
/// Description: Home's sync button for e-amusement scores, showing the
/// running sync's progress from [EamuseSyncState]. Signs in on Konami's own
/// page first when needed.
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
    final signedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const _EamuseSignInPage()));
    if (signedIn == true) state.sync();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EamuseSyncState>();
    final theme = Theme.of(context);
    final syncing = state.status == EamuseStatus.syncing;
    final signedOut = state.status == EamuseStatus.signedOut;
    final at = state.syncedAt;
    final status = switch (state.status) {
      EamuseStatus.syncing => 'Syncing ${(state.progress * 100).round()}%',
      EamuseStatus.signedOut => 'Signed out',
      EamuseStatus.failed => state.error,
      EamuseStatus.idle when at != null => [
          '${state.charts} charts',
          if (state.changed != null)
            state.changed == 0 ? 'no changes' : '${state.changed} updated',
          formatDate(at),
        ].join(' · '),
      EamuseStatus.idle => 'Not synced yet',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child:
                      Text('e-amusement', style: theme.textTheme.titleMedium)),
              PopupMenuButton<void>(
                itemBuilder: (_) => [
                  PopupMenuItem(
                    onTap: signedOut || syncing ? null : state.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(status,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: state.status == EamuseStatus.failed
                              ? theme.colorScheme.error
                              : null)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: syncing
                        ? _ProgressButton(
                            progress: state.progress, onStop: state.stop)
                        : FilledButton.icon(
                            icon: Icon(signedOut ? Icons.login : Icons.sync),
                            label: Text(
                                signedOut
                                    ? 'Sign in'
                                    : state.upToDate
                                        ? 'Up to date'
                                        : 'Sync scores',
                                style: const TextStyle(fontSize: 18)),
                            onPressed: signedOut
                                ? () => _signInAndSync(context)
                                : state.upToDate
                                    ? null
                                    : state.sync,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sync button while it runs: filled to the progress, tap to stop.
class _ProgressButton extends StatelessWidget {
  const _ProgressButton({required this.progress, required this.onStop});

  final double progress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(fit: StackFit.expand, children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: scheme.primaryContainer,
          color: scheme.primary,
        ),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onStop,
            child: Center(
              child: Text('Tap to stop',
                  style: TextStyle(
                      fontSize: 16,
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Konami's sign-in page. Pops true once it lands on the play data pages.
class _EamuseSignInPage extends StatelessWidget {
  const _EamuseSignInPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to e-amusement')),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(kEamuseLoginUrl)),
        onLoadStop: (controller, url) {
          if (url != null &&
              url.host == Uri.parse(kEamuseHost).host &&
              url.path.startsWith(kEamusePlayDataPath)) {
            Navigator.of(context).pop(true);
          }
        },
      ),
    );
  }
}
