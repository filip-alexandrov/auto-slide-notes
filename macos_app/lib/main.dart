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

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<bool> _approvePeer(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect iPad?'),
        content: Text(
          '“$name” wants to receive your screenshots. '
          'Allow it? It will be remembered for next time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return ok ?? false;
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

  Future<void> _toggleRegionOutline() async {
    final region = _region;
    if (region == null) return;
    if (_showingRegion) {
      await ScreenCapture.hideRegion();
    } else {
      await ScreenCapture.showRegion(region);
    }
    setState(() => _showingRegion = !_showingRegion);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_prefs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final region = _region;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LinkCard(link: _link),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.crop_free),
                title: Text(
                  region == null ? 'No region selected' : 'Capture region',
                ),
                subtitle: region == null
                    ? const Text('Choose the part of the screen to capture.')
                    : Text(
                        'x ${region.left.round()}, y ${region.top.round()} · '
                        '${region.width.round()} × ${region.height.round()} pt',
                      ),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.settings_overscan),
                  label: Text(region == null ? 'Select…' : 'Change…'),
                  onPressed: _busy ? null : _selectRegion,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: Icon(
                _showingRegion ? Icons.visibility_off : Icons.visibility,
              ),
              label: Text(
                _showingRegion ? 'Hide capture area' : 'Show capture area',
              ),
              onPressed: region == null ? null : _toggleRegionOutline,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Keep this window on top'),
              value: _alwaysOnTop,
              onChanged: (v) async {
                final value = v ?? false;
                await ScreenCapture.setAlwaysOnTop(value);
                await _prefs?.setBool(_kOnTop, value);
                setState(() => _alwaysOnTop = value);
              },
            ),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.keyboard_outlined),
                title: const Text('Screenshot shortcut'),
                subtitle: Text(
                  !_hotKeyEnabled
                      ? 'Off'
                      : _hotKeyRegistered
                      ? 'Works in any app.'
                      : 'Already used by another app — choose another.',
                  style: _hotKeyEnabled && !_hotKeyRegistered
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _KeyCap(_hotKey.label, enabled: _hotKeyEnabled),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _changeHotKey,
                      child: const Text('Change…'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) async {
                        switch (v) {
                          case 'toggle':
                            final value = !_hotKeyEnabled;
                            await _prefs?.setBool(_kHotKeyEnabled, value);
                            setState(() => _hotKeyEnabled = value);
                            await _applyHotKey();
                          case 'reset':
                            await _resetHotKey();
                        }
                      },
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: 'toggle',
                          checked: _hotKeyEnabled,
                          child: const Text('Enabled'),
                        ),
                        PopupMenuItem(
                          value: 'reset',
                          enabled: !_hotKey.isDefault,
                          child: Text(
                            'Reset to ${HotKeySpec.defaultSpec.label}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_hasPermission == false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Screen Recording permission not granted yet — you will be '
                  'asked on the first screenshot.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_camera),
                label: Text(
                  _hotKeyEnabled
                      ? 'Screenshot  (${_hotKey.label})'
                      : 'Screenshot',
                  style: const TextStyle(fontSize: 18),
                ),
                onPressed: region == null || _busy ? null : _screenshot,
              ),
            ),
            const SizedBox(height: 12),
            if (_status != null)
              Text(
                _status!,
                style: TextStyle(
                  color: _statusIsError
                      ? theme.colorScheme.error
                      : Colors.green[700],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                child: _lastImage == null
                    ? Text(
                        'Last screenshot appears here',
                        style: theme.textTheme.bodySmall,
                      )
                    : Image.memory(_lastImage!, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
