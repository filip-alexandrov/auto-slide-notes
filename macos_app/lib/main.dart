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

  @override
  void initState() {
    super.initState();
    ScreenCapture.setHotKeyHandler(() => _screenshot(fromShortcut: true));
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final regionJson = prefs.getString(_kRegion);
    Rect? region;
    if (regionJson != null) {
      final m = (jsonDecode(regionJson) as Map).cast<String, num>();
      region = Rect.fromLTWH(
        m['x']!.toDouble(),
        m['y']!.toDouble(),
        m['width']!.toDouble(),
        m['height']!.toDouble(),
      );
    }
    final onTop = prefs.getBool(_kOnTop) ?? false;
    if (onTop) await ScreenCapture.setAlwaysOnTop(true);
    final hasPermission = await ScreenCapture.hasPermission();
    final hotKeyJson = prefs.getString(_kHotKey);
    _hotKey =
        (hotKeyJson == null
            ? null
            : HotKeySpec.fromJson(jsonDecode(hotKeyJson) as Map)) ??
        HotKeySpec.defaultSpec;
    _hotKeyEnabled = prefs.getBool(_kHotKeyEnabled) ?? true;
    await _applyHotKey();
    setState(() {
      _prefs = prefs;
      _region = region;
      _alwaysOnTop = onTop;
      _hasPermission = hasPermission;
    });
  }

  void _setStatus(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusIsError = error;
    });
  }

  Future<void> _selectRegion() async {
    final region = await ScreenCapture.selectRegion();
    // The selection overlay hides the outline; bring it back (for the new
    // region, or the old one if the user cancelled).
    if (_showingRegion && (region ?? _region) != null) {
      await ScreenCapture.showRegion((region ?? _region)!);
    }
    if (region == null) return;
    await _prefs?.setString(
      _kRegion,
      jsonEncode({
        'x': region.left,
        'y': region.top,
        'width': region.width,
        'height': region.height,
      }),
    );
    setState(() => _region = region);
    _setStatus('Region saved.');
  }

  Future<void> _screenshot({bool fromShortcut = false}) async {
    final region = _region;
    if (_busy) return;
    if (region == null) {
      _setStatus('Select a capture region first.', error: true);
      if (fromShortcut) await ScreenCapture.playFeedback(success: false);
      return;
    }
    setState(() => _busy = true);
    var ok = false;
    try {
      if (!await ScreenCapture.hasPermission()) {
        await ScreenCapture.requestPermission();
        setState(() => _hasPermission = false);
        _setStatus(
          'Screen Recording permission is required. Enable it in System Settings '
          '› Privacy & Security › Screen Recording, then restart the app.',
          error: true,
        );
        return;
      }
      final png = await ScreenCapture.capture(region);
      setState(() => _lastImage = png);
      final id = await _link.send(png);
      ok = true;
      _setStatus(
        _link.peers.isEmpty
            ? 'Slide #$id queued — it will be sent when an iPad connects.'
            : 'Slide #$id sent to ${_link.peers.join(', ')}.',
      );
    } catch (e) {
      _setStatus('Failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      // The window may be hidden behind the slides; confirm by sound.
      if (fromShortcut) await ScreenCapture.playFeedback(success: ok);
    }
  }
}
