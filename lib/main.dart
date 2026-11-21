import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

const String TARGET_URL = 'https://surfer-winner-daybed.ngrok-free.dev';
const Map<String, String> NGROK_HEADERS = {
  'ngrok-skip-browser-warning': 'true',
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
};

// 给页面内所有 fetch / XHR 子请求统一补上 ngrok 放行头
const String FETCH_PATCH = """
(function() {
  if (window.__ngrokPatched) return;
  window.__ngrokPatched = true;

  // 1) 补丁 fetch
  var origFetch = window.fetch;
  window.fetch = function(input, init) {
    init = init || {};
    init.headers = init.headers || {};
    try {
      if (init.headers instanceof Headers) {
        init.headers.set('ngrok-skip-browser-warning', 'true');
      } else if (Array.isArray(init.headers)) {
        init.headers.push(['ngrok-skip-browser-warning', 'true']);
      } else {
        init.headers['ngrok-skip-browser-warning'] = 'true';
      }
    } catch (e) {}
    return origFetch.call(this, input, init);
  };

  // 2) 补丁 XMLHttpRequest
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function() {
    this.__ngrokHeaderAdded = false;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function() {
    try {
      if (!this.__ngrokHeaderAdded) {
        this.setRequestHeader('ngrok-skip-browser-warning', 'true');
        this.__ngrokHeaderAdded = true;
      }
    } catch (e) {}
    return origSend.apply(this, arguments);
  };
})();
""";

// 每 3 秒探测一次；连续 N 次仍没好友就放弃，避免“真没好友”时无限刷新
const int MAX_RELOAD = 12;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.microphone.request();
  await Permission.camera.request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BrowserScreen(),
    );
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  bool _loading = true;
  InAppWebViewController? _controller;
  Timer? _probeTimer;

  bool _friendListReady = false; // 好友列表已渲染出来，永久停止检测
  int _reloadCount = 0;          // 已自动重新加载的次数

  @override
  void initState() {
    super.initState();
    // 周期探测：登录是 SPA 内完成的、不会再触发 onLoadStop，
    // 所以用 repeating Timer 比“onLoadStop 后只查一次”更稳。
    _probeTimer = Timer.periodic(const Duration(seconds: 3), (_) => _probe());
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  /// 每 3 秒执行：登录了吗？好友渲染出来了吗？没出来就重新加载（带 ngrok 头）。
  Future<void> _probe() async {
    if (_controller == null || !mounted) return;
    if (_friendListReady) return;

    String status = 'WAIT_LOGIN';
    try {
      final res = await _controller!.evaluateJavascript(
        source: """
        (function() {
          try {
            var lv = document.getElementById('loginView');
            // 登录页 CSS 默认 flex；登录成功后被设成 none
            var logged = lv && getComputedStyle(lv).display === 'none';
            if (!logged) return 'WAIT_LOGIN';
            var cards = document.querySelectorAll('#friendsGrid .device-card').length;
            return cards > 0 ? 'READY' : 'NOT_READY';
          } catch (e) {
            return 'WAIT_LOGIN';
          }
        })();
        """,
      );
      final s = (res ?? '').toString();
      if (s.contains('READY') && !s.contains('NOT_READY')) {
        status = 'READY';
      } else if (s.contains('NOT_READY')) {
        status = 'NOT_READY';
      } else if (s.contains('WAIT_LOGIN')) {
        status = 'WAIT_LOGIN';
      }
    } catch (e) {
      return; // JS 还没就绪，下一轮再看
    }

    if (status == 'READY') {
      // 好友刷出来了 → 标记完成，停掉定时器，不再有任何自动刷新
      _friendListReady = true;
      _probeTimer?.cancel();
      return;
    }

    if (status == 'NOT_READY') {
      // 已登录但好友没渲染出来：还没到上限就重新加载主文档（带 ngrok 头）
      if (_reloadCount < MAX_RELOAD) {
        _reloadCount++;
        _reloadWithHeaders();
      } else {
        // 达到上限仍没有好友：要么真的没好友，要么环境问题 reload 也救不了，停手
        _probeTimer?.cancel();
      }
    }
    // WAIT_LOGIN：用户还在登录页，什么都不做，不打断输入
  }

  /// 用带 ngrok 头的 URLRequest 重新加载（不要用 reload()，那样不带放行头）
  void _reloadWithHeaders() {
    _controller?.loadUrl(
      urlRequest: URLRequest(url: Uri.parse(TARGET_URL), headers: NGROK_HEADERS),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: Uri.parse(TARGET_URL),
                headers: NGROK_HEADERS,
              ),
              initialUserScripts: UnmodifiableListView<UserScript>([
                UserScript(
                  groupName: 'ngrok',
                  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  source: FETCH_PATCH,
                ),
              ]),
              initialOptions: InAppWebViewGroupOptions(
                crossPlatform: InAppWebViewOptions(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                ),
                ios: IOSInAppWebViewOptions(
                  allowsInlineMediaPlayback: true,
                ),
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (controller, url) {
                if (mounted) setState(() => _loading = false);
              },
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}