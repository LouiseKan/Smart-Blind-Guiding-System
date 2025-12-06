import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart'; // for SemanticsService.announce
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p; // 導入 path 套件來處理路徑
import 'dart:io';

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
      ),
      home: const HomePage(),
    );
  }
}
const String _apiEndpoint = 'http://10.204.1.106:5000/detect_crosswalk';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> {
  // detection state
  bool _isDetecting = false;
  bool _muteVoice = false;
  Timer? _timer;
  DetectionResult? _last;
  DateTime? _lastFrameTime;
  bool _isUploading = false;

  // tts
  final _tts = FlutterTts();

  // camera
  CameraController? _cameraController;
  bool _cameraReady = false;

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
    // 注意：permission_handler 12 回傳 Map<Permission, PermissionStatus>
    final statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
      Permission.storage,
    ].request();

    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    if (camOk) {
      await _initCamera();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相機權限才能顯示預覽')),
        );
      }
    }

    if (!locOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('之後使用地圖時需要定位權限')),
      );
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('相機初始化失敗：$e')),
        );
      }
    }
  }

// 1. 網路請求函式：負責拍照、上傳和下載 JSON
  Future<String?> _sendImageToBackend(XFile image) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(_apiEndpoint))
        ..files.add(
          await http.MultipartFile.fromPath(
            'image', // 必須與 app.py 中的 request.files['image'] 匹配
            image.path,
            filename: p.basename(image.path),
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // 🚨 關鍵新增：確保檔案被刪除，釋放相機緩衝區
      try {
        final fileToDelete = File(image.path);
        await fileToDelete.delete(); // 呼叫 dart:io.File 的 delete()
        print('✅ 臨時圖片檔案已刪除，釋放相機緩衝區。');
      } catch (e) {
        // 如果刪除失敗，這可能只是權限問題，App 仍可繼續
        print('警告: 無法刪除臨時圖片檔案 $e');
      }

      if (response.statusCode == 200) {
        print('✅ API 連線成功，偵測結果已回傳。'); // <-- 新增這行
        return response.body; // 成功回傳 JSON 字串
      } else {
        print('API 請求失敗: ${response.statusCode}, Body: ${response.body}');
        // 可以在這裡播報語音警告
        _tts.speak("網路連線錯誤，代碼${response.statusCode}");
        return null;
      }
    } catch (e, stacktrace) {
      print('❌ 網路連線/上傳錯誤: $e');
      print('堆疊追蹤: $stacktrace');
      // 可以在這裡播報語音警告
      _tts.speak("無法連線到偵測伺服器");
      return null;
    }
  }

// 2. 解析後端 JSON 函式：將 YOLOv8 結果轉換為 App 的 DetectionResult 格式
  DetectionResult _parseBackendJson(String jsonStr) {
    final List<dynamic> jsonList = json.decode(jsonStr);
    final List<DetectionObject> objects = [];

    for (var json in jsonList) {
      // ⚠️ 注意：後端只回傳 label, confidence, bbox。
      // App 需要 'direction' 欄位，我們必須根據 bbox 座標來計算。

      final double xMin = json['bbox']['x_min'] ?? 0.0;
      final double xMax = json['bbox']['x_max'] ?? 0.0;

      // 簡單的 'direction' 判斷邏輯 (可以根據您的 App 需求調整)
      // 假設螢幕/圖片寬度為 800 (因為我們用 imgsz=800 推論)
      // 雖然這個判斷比較粗糙，但可以用來測試。
      final double center = (xMin + xMax) / 2;
      String direction;

      if (center < 300) { // 偏左
        direction = 'left';
      } else if (center > 500) { // 偏右
        direction = 'right';
      } else { // 接近中央
        direction = 'ahead';
      }

      objects.add(
          DetectionObject(
            label: (json['label'] ?? '').toString(),
            direction: direction,
            confidence: (json['confidence'] ?? 0).toDouble(),
          )
      );
    }

    return DetectionResult(
      timestamp: DateTime.now(),
      objects: objects,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.stop();
    _cameraController?.dispose();
    super.dispose();
  }

  // ... 其他程式碼 ...

  void _startDetection() {
    if (_isDetecting) return;
    if (!_cameraReady || _cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('相機尚未初始化或連線失敗')),
      );
      return;
    }

    setState(() => _isDetecting = true);

    // 🚨 關鍵修改：將循環間隔縮短到 2.5 秒 (可以根據性能調整)
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      if (_isUploading) return;

      _isUploading = true; // 鎖定
      _lastFrameTime = DateTime.now();

      try {
        // 1. 拍照取得圖片檔案 (這是關鍵的實時幀抓取)
        final XFile image = await _cameraController!.takePicture();

        // 2. 將圖片傳送給後端 API 進行偵測
        final jsonResponse = await _sendImageToBackend(image);

        if (jsonResponse != null) {
          // 3. 解析從後端取得的 JSON
          final result = _parseBackendJson(jsonResponse);
          await _handleDetections(result);
        } else {
          // 網路錯誤或偵測失敗，_handleDetections 不會被呼叫，保持 _last 不變
        }

      } catch (e) {
        print('拍照或 API 失敗: $e');
        // 拍照失敗（例如連續拍照過快）通常會導致錯誤，忽略即可
      }
    });
  }

// ... 其他程式碼 ...

  void _stopDetection() {
    _timer?.cancel();
    _timer = null;
    setState(() => _isDetecting = false);
  }

  Future<void> _handleDetections(DetectionResult result) async {
    setState(() => _last = result);

    final top = result.topPriorityMessage();
    if (top != null) {
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
            _StatusBar(
              isDetecting: _isDetecting,
              last: _last,
              lastFrameTime: _lastFrameTime,
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_cameraReady &&
                      _cameraController != null &&
                      _cameraController!.value.isInitialized)
                    CameraPreview(_cameraController!)
                  else
                    const _CameraPreviewPlaceholder(isReady: false),
                  _DetectionOverlay(result: _last),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isDetecting ? _stopDetection : _startDetection,
                      icon: Icon(_isDetecting ? Icons.stop : Icons.play_arrow),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      label: Text(_isDetecting ? '停止偵測' : '開始偵測'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MapPage()),
                        );
                      },
                      icon: const Icon(Icons.map),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      label: const Text('地圖'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => setState(() => _muteVoice = !_muteVoice),
                    iconSize: 32,
                    tooltip: _muteVoice ? '開啟語音播報' : '靜音',
                    icon: Icon(_muteVoice ? Icons.volume_off : Icons.volume_up),
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
    final timeStr =
    lastFrameTime == null ? '' : '  ·  上次更新 ${TimeOfDay.fromDateTime(lastFrameTime!).format(context)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: color.withOpacity(0.15),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$text｜$lastMsg$timeStr',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: .5)),
          ),
        ],
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
          gradient: LinearGradient(
            colors: [Colors.black.withOpacity(0.9), Colors.blueGrey.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
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
                  ? Icons.directions_walk // fallback (有些 SDK 沒有 crosswalk)
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
                    Text('(${(o.confidence * 100).toStringAsFixed(0)}%)'),
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
      body: const Center(child: Text('這裡將換成 GoogleMap 小元件')),
    );
  }
}

// ======= Data Model & Parser =======
class DetectionObject {
  final String label; // 'zebra_crossing', 'car'
  final String direction; // 'right_ahead', 'left', 'ahead'
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
