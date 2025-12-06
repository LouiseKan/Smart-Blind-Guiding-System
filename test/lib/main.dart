import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/semantics.dart';

// If you plan to preview camera & map, add these packages to pubspec.yaml and wire them up:
// camera: ^0.11.0
// google_maps_flutter: ^2.7.0
// geolocator: ^13.0.1
// For this UI skeleton, camera preview shows a placeholder until you integrate the real controller.
// Map page is included but centers on a fallback LatLng until you connect location services.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlindVisionApp());
}

class BlindVisionApp extends StatelessWidget {
  const BlindVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Blind Vision Assistant',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18),
          bodyMedium: TextStyle(fontSize: 16),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        // High-contrast, large tap targets
        visualDensity: VisualDensity.comfortable,
        splashFactory: InkRipple.splashFactory,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _tts = FlutterTts();
  bool _isDetecting = false;
  bool _muteVoice = false;
  Timer? _timer;
  DetectionResult? _last;
  DateTime? _lastFrameTime;

  @override
  void initState() {
    super.initState();
    _initTts();
    _requestPermissions();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('zh-TW');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.locationWhenInUse].request();
    // Optionally: microphone, if you want voice commands.
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.stop();
    super.dispose();
  }

  void _startDetection() {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);

    // Every 5 seconds, simulate grabbing a frame + reading a JSON result.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      _lastFrameTime = DateTime.now();

      // TODO: Replace this mock with your actual JSON from the detection model.
      final mockJson = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'objects': [
          {
            'label': 'zebra_crossing',
            'direction': 'right_ahead',
            'confidence': 0.92,
          },
          {
            'label': 'car',
            'direction': 'left',
            'confidence': 0.71,
          }
        ]
      });

      final result = parseJsonFrame(mockJson);
      _handleDetections(result);
    });
  }

  void _stopDetection() {
    _timer?.cancel();
    _timer = null;
    setState(() => _isDetecting = false);
  }

  Future<void> _handleDetections(DetectionResult result) async {
    setState(() => _last = result);

    final top = result.topPriorityMessage();

    // Announce via system accessibility (TalkBack/VoiceOver) + TTS + haptics.
    if (top != null) {
      // System announce (respects screen reader)
      // NOTE: Works best when a11y services are enabled on device.
      SemanticsService.announce(top, TextDirection.ltr);

      if (!_muteVoice) {
        await _tts.stop();
        await _tts.speak(top);
      }

      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [0, 250, 150, 300]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top status & last message banner
            _StatusBar(
              isDetecting: _isDetecting,
              last: _last,
              lastFrameTime: _lastFrameTime,
            ),
            // Camera + overlay
            Expanded(
              child: Stack(
                children: [
                  _CameraPreviewPlaceholder(isReady: _isDetecting),
                  _DetectionOverlay(result: _last),
                ],
              ),
            ),
            // Controls
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: _isDetecting ? '停止偵測' : '開始偵測',
                      child: ElevatedButton.icon(
                        onPressed: _isDetecting ? _stopDetection : _startDetection,
                        icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        label: Text(_isDetecting ? '停止偵測' : '開始偵測'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: '開啟地圖',
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MapPage()),
                          );
                        },
                        icon: const Icon(Icons.map),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        label: const Text('地圖'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: _muteVoice ? '開啟語音播報' : '靜音',
                    child: IconButton(
                      onPressed: () => setState(() => _muteVoice = !_muteVoice),
                      iconSize: 32,
                      tooltip: _muteVoice ? '開啟語音播報' : '靜音',
                      icon: Icon(_muteVoice ? Icons.volume_off : Icons.volume_up),
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

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.isDetecting,
    required this.last,
    required this.lastFrameTime,
  });

  final bool isDetecting;
  final DetectionResult? last;
  final DateTime? lastFrameTime;

  @override
  Widget build(BuildContext context) {
    final text = isDetecting ? '偵測中…' : '待機';
    final color = isDetecting ? Colors.green : Colors.grey;

    final lastMsg = last?.topPriorityMessage() ?? '尚無偵測結果';
    final timeStr = lastFrameTime == null
        ? ''
        : '  ·  上次更新 ${TimeOfDay.fromDateTime(lastFrameTime!).format(context)}';

    return Semantics(
      container: true,
      label: '目前狀態 $text。$lastMsg',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: color.withOpacity(0.15),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$text｜$lastMsg$timeStr',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(letterSpacing: .5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraPreviewPlaceholder extends StatelessWidget {
  const _CameraPreviewPlaceholder({required this.isReady});
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '相機預覽',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.black.withOpacity(0.9),
            Colors.blueGrey.shade900,
          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isReady ? Icons.videocam : Icons.videocam_off, size: 72),
            const SizedBox(height: 12),
            Text(isReady ? '相機連線中…' : '相機尚未啟動', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            const Text('（整合 camera 套件後會顯示即時畫面）'),
          ],
        ),
      ),
    );
  }
}

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay({this.result});
  final DetectionResult? result;

  @override
  Widget build(BuildContext context) {
    final res = result;
    if (res == null || res.objects.isEmpty) return const SizedBox.shrink();

    // A pill-style overlay list in the upper area.
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: res.objects.map((o) {
              final icon = o.label == 'zebra_crossing'
                  ? Icons.directions_walk
                  : Icons.directions_car;
              final dirText = _dirText(o.direction);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 6),
                    Text('${_labelText(o.label)}｜$dirText'),
                    const SizedBox(width: 6),
                    Text('(${(o.confidence * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static String _labelText(String raw) {
    switch (raw) {
      case 'zebra_crossing':
        return '斑馬線';
      case 'car':
        return '車輛';
      default:
        return raw;
    }
  }

  static String _dirText(String raw) {
    switch (raw) {
      case 'left':
        return '左側';
      case 'right':
        return '右側';
      case 'ahead':
        return '前方';
      case 'right_ahead':
        return '右前方';
      case 'left_ahead':
        return '左前方';
      default:
        return raw;
    }
  }
}

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('附近路況（地圖）')),
      body: const _MapPlaceholder(),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    // Replace with GoogleMap widget once API Key is set.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.map, size: 72),
          SizedBox(height: 12),
          Text('這裡會顯示 Google Map'),
          SizedBox(height: 4),
          Text('（設定 API Key 後用 google_maps_flutter 取代）'),
        ],
      ),
    );
  }
}

// ======= Data Model & Parser =======
class DetectionObject {
  final String label; // e.g., 'zebra_crossing', 'car'
  final String direction; // e.g., 'right_ahead', 'left', 'ahead'
  final double confidence; // 0~1
  const DetectionObject({required this.label, required this.direction, required this.confidence});

  factory DetectionObject.fromJson(Map<String, dynamic> m) => DetectionObject(
    label: (m['label'] ?? '').toString(),
    direction: (m['direction'] ?? '').toString(),
    confidence: (m['confidence'] ?? 0).toDouble(),
  );
}

class DetectionResult {
  final DateTime timestamp;
  final List<DetectionObject> objects;
  const DetectionResult({required this.timestamp, required this.objects});

  /// Convert top priority object to an announcement string in Chinese.
  /// Priority rule (you can tweak): zebra_crossing > car; higher confidence first.
  String? topPriorityMessage() {
    if (objects.isEmpty) return null;
    final sorted = [...objects]
      ..sort((a, b) {
        final priA = a.label == 'zebra_crossing' ? 1 : 0;
        final priB = b.label == 'zebra_crossing' ? 1 : 0;
        final c = priB.compareTo(priA);
        if (c != 0) return c;
        return b.confidence.compareTo(a.confidence);
      });
    final top = sorted.first;
    final label = top.label == 'zebra_crossing' ? '斑馬線' : (top.label == 'car' ? '車輛' : top.label);

    String dir;
    switch (top.direction) {
      case 'right':
        dir = '右側';
        break;
      case 'left':
        dir = '左側';
        break;
      case 'ahead':
        dir = '前方';
        break;
      case 'right_ahead':
        dir = '右前方';
        break;
      case 'left_ahead':
        dir = '左前方';
        break;
      default:
        dir = top.direction;
    }
    return '注意，$dir有$label。';
  }
}

DetectionResult parseJsonFrame(String jsonStr) {
  final m = jsonDecode(jsonStr) as Map<String, dynamic>;
  final ts = DateTime.tryParse((m['timestamp'] ?? '').toString()) ?? DateTime.now();
  final list = (m['objects'] as List<dynamic>? ?? [])
      .map((e) => DetectionObject.fromJson(e as Map<String, dynamic>))
      .toList();
  return DetectionResult(timestamp: ts, objects: list);
}

/* =========================
HOW TO INTEGRATE (quick notes)

pubspec.yaml (add and `flutter pub get`):

dependencies:
  flutter:
    sdk: flutter
  flutter_tts: ^3.8.5
  permission_handler: ^11.3.1
  vibration: ^1.9.0
  # For live camera preview & frame extraction:
  camera: ^0.11.0
  # For map:
  google_maps_flutter: ^2.7.0

Android setup:
- Add your Google Maps API key to android/app/src/main/AndroidManifest.xml:
  <meta-data android:name="com.google.android.geo.API_KEY" android:value="YOUR_API_KEY"/>
- Request camera & location permissions in the Manifest as required by packages.

Camera wiring (replace placeholder):
- Create a CameraController with the back camera.
- Start video stream or periodic image stream; on every 5 seconds, pull one frame (or the latest)
  and send to your detection service; parse returned JSON; call _handleDetections().

Accessibility tips:
- Keep buttons big (56px+) and labels clear.
- Always provide Semantics labels for non-text UI.
- Use TTS + SemanticsService.announce for real-time alerts.
- Provide a mute toggle and concise, consistent phrasing (e.g., 「注意，右前方有斑馬線。」).

========================= */
