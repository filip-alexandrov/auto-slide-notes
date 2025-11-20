import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screen_capture.dart';
import 'slide_link.dart';

const _kRegion = 'region';
const _kOnTop = 'alwaysOnTop';
const _kHotKey = 'hotKey';
const _kHotKeyEnabled = 'hotKeyEnabled';

void main() {
  runApp(const MacCaptureApp());
}

class MacCaptureApp extends StatelessWidget {
  const MacCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slide Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E5EFF)),
        useMaterial3: true,
      ),
      home: const CaptureScreen(),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  SharedPreferences? _prefs;
  late final SlideLink _link = SlideLink(approvePeer: _approvePeer)
    ..addListener(() {
      if (mounted) setState(() {});
    });
  Rect? _region;
  bool _alwaysOnTop = false;
  HotKeySpec _hotKey = HotKeySpec.defaultSpec;
  bool _hotKeyEnabled = true;

  /// False when macOS refused the shortcut (another app owns it).
  bool _hotKeyRegistered = true;
  bool _showingRegion = false;
  bool _busy = false;
  bool? _hasPermission;
  Uint8List? _lastImage;
  String? _status;
  bool _statusIsError = false;
}
