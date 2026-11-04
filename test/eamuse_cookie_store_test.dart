import 'dart:async';

import 'package:ddr_md/models/eamuse.dart';
import 'package:ddr_md/models/eamuse_cookie_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Browser extends InAppWebViewPlatform {
  final views = <_View>[];
  bool autoLoad = true;
  bool failRun = false;
  bool loaded = false;
  bool terminateOnRead = false;
  int reads = 0;
  WebUri? readUrl;

  void reset() {
    views.clear();
    autoLoad = true;
    failRun = false;
    loaded = false;
    terminateOnRead = false;
    reads = 0;
    readUrl = null;
  }

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams params) {
    final view = _View(params, this);
    views.add(view);
    return view;
  }

  @override
  PlatformCookieManager createPlatformCookieManager(
          PlatformCookieManagerCreationParams params) =>
      _Cookies(params, this);
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 'test'));
}

class _View extends PlatformHeadlessInAppWebView {
  _View(super.params, this.browser) : super.implementation();
  final _Browser browser;
  late final controller = params.controllerFromPlatform!(_Controller());
  int disposals = 0;

  @override
  Future<void> run() async {
    if (browser.failRun) throw StateError('WebKit did not start');
    if (browser.autoLoad) finishLoading();
  }

  void finishLoading() {
    browser.loaded = true;
    params.onLoadStop?.call(controller, WebUri('about:blank'));
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.browser) : super.implementation();
  final _Browser browser;

  @override
  Future<List<Cookie>> getCookies(
      {required WebUri url,
      PlatformInAppWebViewController? iosBelow11WebViewController,
      PlatformInAppWebViewController? webViewController}) async {
    browser.reads++;
    browser.readUrl = url;
    if (browser.terminateOnRead) {
      browser.loaded = false;
      final view = browser.views.last;
      view.params.onWebContentProcessDidTerminate?.call(view.controller);
      return [];
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && !browser.loaded) {
      return [];
    }
    return [Cookie(name: 'M573SSID', value: 'saved-login')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final browser = _Browser();
  InAppWebViewPlatform.instance = browser;
  late EamuseCookieStore store;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    browser.reset();
    store = EamuseCookieStore();
  });

  tearDown(() async {
    await store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('cold-start reads wait for WebKit and reuse the saved login', () async {
    browser.autoLoad = false;
    final first = store.read();
    final second = store.read();
    expect(browser.views, hasLength(1));
    expect(browser.reads, 0);
    final view = browser.views.single;
    expect(view.params.initialUrlRequest?.url.toString(), 'about:blank');
    expect(view.params.initialSettings?.incognito, false);
    expect(view.params.initialSettings?.cacheEnabled, true);

    view.finishLoading();
    expect(await first, 'M573SSID=saved-login');
    expect(await second, 'M573SSID=saved-login');
    expect(await store.read(), 'M573SSID=saved-login');
    expect(browser.readUrl.toString(), eamuseRecentUrl().toString());
    expect(browser.views, hasLength(1));
    expect(view.disposals, 0);
  });

  test('a failed initialization reads no cookies and can be retried', () async {
    browser.failRun = true;
    await expectLater(store.read(), throwsStateError);
    expect(browser.reads, 0);
    expect(browser.views.single.disposals, 1);

    browser.failRun = false;
    expect(await store.read(), 'M573SSID=saved-login');
    expect(browser.views, hasLength(2));
  });

  test('a terminated WebKit process is recreated before reading again',
      () async {
    await store.read();
    final first = browser.views.single;
    browser.loaded = false;
    first.params.onWebContentProcessDidTerminate?.call(first.controller);
    expect(await store.read(), 'M573SSID=saved-login');
    expect(browser.views, hasLength(2));
    expect(first.disposals, 1);
  });

  testWidgets(
      'an unresponsive WebKit startup times out without reading cookies',
      (tester) async {
    browser.autoLoad = false;
    final failed = expectLater(store.read(), throwsA(isA<TimeoutException>()));
    await tester.pump(const Duration(seconds: 10));
    await failed;
    expect(browser.reads, 0);
    expect(browser.views.single.disposals, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a process exit during a cookie read cannot send an anonymous session',
      () async {
    browser.terminateOnRead = true;
    await expectLater(store.read(), throwsStateError);
    expect(browser.views.single.disposals, 1);

    browser.terminateOnRead = false;
    expect(await store.read(), 'M573SSID=saved-login');
    expect(browser.views, hasLength(2));
  });

  test('disposing during startup cancels the pending read', () async {
    browser.autoLoad = false;
    final failed = expectLater(store.read(), throwsStateError);
    await store.dispose();
    await failed;
    expect(browser.reads, 0);
    expect(browser.views.single.disposals, 1);
    await expectLater(store.read(), throwsStateError);
  });

  test('Android uses its cookie store without starting a hidden browser',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await store.read(), 'M573SSID=saved-login');
    expect(browser.views, isEmpty);
  });
}
