import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: Uri.parse('https://surfer-winner-daybed.ngrok-free.dev'),
                headers: const {
                  'ngrok-skip-browser-warning': 'true',
                  'User-Agent':
                      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
                      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
                },
              ),
              initialOptions: InAppWebViewGroupOptions(
                crossPlatform: InAppWebViewOptions(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  debuggingEnabled: true,
                ),
                ios: IOSInAppWebViewOptions(
                  allowsInlineMediaPlayback: true,
                ),
              ),
              onPermissionRequest: (controller, request) async {
                final perms = request.resources;
                final needMic = perms.contains(
                  PermissionRequestResourceType.AUDIO_CAPTURE,
                );
                final needCam = perms.contains(
                  PermissionRequestResourceType.VIDEO_CAPTURE,
                );

                bool ok = true;
                if (needMic) {
                  ok = ok && (await Permission.microphone.request()).isGranted;
                }
                if (needCam) {
                  ok = ok && (await Permission.camera.request()).isGranted;
                }

                if (ok) {
                  await request.grant();
                } else {
                  await request.deny();
                }
              },
              onLoadStart: (_) {
                if (mounted) setState(() => _loading = true);
              },
              onLoadStop: (_) {
                if (mounted) setState(() => _loading = false);
              },
              onReceivedError: (controller, request, error) {
                debugPrint('加载失败: ${error.description}');
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