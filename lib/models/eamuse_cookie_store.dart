/// Name: EamuseCookieStore
/// Parent: EamuseSyncState
/// Description: Reads the browser's saved e-amusement login after WebKit has
/// opened its persistent cookie store, before any score request can replace
/// the saved session with an anonymous one.
library;

import 'dart:async';

import 'package:ddr_md/models/eamuse.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class EamuseCookieStore {
  HeadlessInAppWebView? _view;
  Future<void>? _ready;
  Completer<void>? _loading;
  bool _disposed = false;

  Future<String> read() async {
    if (_disposed) throw StateError('Cookie store disposed');
    final ready = _ready ??= _prepare();
    try {
      await ready;
    } catch (_) {
      if (identical(_ready, ready)) _ready = null;
      rethrow;
    }
    if (_disposed) throw StateError('Cookie store disposed');
    if (!identical(_ready, ready)) {
      throw StateError('Browser cookie process stopped');
    }
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri(eamuseRecentUrl().toString()));
    // A WebKit process can exit while the native read is in flight. Its empty
    // reply must not turn a valid saved login into an anonymous score request.
    if (_disposed || !identical(_ready, ready)) {
      throw StateError('Browser cookie process stopped');
    }
    return [for (final cookie in cookies) '${cookie.name}=${cookie.value}']
        .join('; ');
  }

  Future<void> _prepare() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    final loaded = _loading = Completer<void>();
    late final HeadlessInAppWebView view;
    view = _view = HeadlessInAppWebView(
      // A local blank page starts WebKit without contacting Konami or changing
      // its cookies. Keep it alive so subsequent cookie reads and writes use
      // the same persistent store as the visible sign-in browser.
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings:
          InAppWebViewSettings(incognito: false, cacheEnabled: true),
      onLoadStop: (_, url) {
        if (url?.toString() == 'about:blank' && !loaded.isCompleted) {
          loaded.complete();
        }
      },
      onReceivedError: (_, request, __) {
        if (request.isForMainFrame != false && !loaded.isCompleted) {
          loaded
              .completeError(StateError('Could not open browser cookie store'));
        }
      },
      onWebContentProcessDidTerminate: (_) {
        if (!loaded.isCompleted) {
          loaded.completeError(StateError('Browser cookie process stopped'));
        }
        if (identical(_view, view)) {
          _view = null;
          _ready = null;
          unawaited(view.dispose());
        }
      },
    );
    try {
      await Future.wait([loaded.future, view.run()], eagerError: true)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      if (identical(_view, view)) {
        _view = null;
        await view.dispose();
      }
      rethrow;
    } finally {
      if (identical(_loading, loaded)) _loading = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final view = _view;
    _view = null;
    if (_loading case final loading? when !loading.isCompleted) {
      loading.completeError(StateError('Cookie store disposed'));
    }
    await view?.dispose();
  }
}
