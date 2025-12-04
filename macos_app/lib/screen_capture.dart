import 'package:flutter/services.dart';

/// Dart side of the native `mac_capture/screen` channel
/// (see macos/Runner/MainFlutterWindow.swift).
///
/// Rects are in global points with the origin at the top-left of the
/// primary display; secondary displays may have negative coordinates.
class ScreenCapture {
  static const _channel = MethodChannel('mac_capture/screen');

  /// Shows a full-screen overlay on every display and returns the dragged
  /// rectangle, or null if the user cancelled.
  static Future<Rect?> selectRegion() async {
    final r = await _channel.invokeMapMethod<String, double>('selectRegion');
    if (r == null) return null;
    return Rect.fromLTWH(r['x']!, r['y']!, r['width']!, r['height']!);
  }

  /// Captures [region] as PNG bytes (at the display's native resolution).
  static Future<Uint8List> capture(Rect region) async {
    final bytes = await _channel.invokeMethod<Uint8List>('capture', {
      'x': region.left,
      'y': region.top,
      'width': region.width,
      'height': region.height,
    });
    return bytes!;
  }

  /// Outlines [region] on screen (the outline is drawn just outside it, so
  /// it never shows up in captures).
  static Future<void> showRegion(Rect region) =>
      _channel.invokeMethod('showRegion', {
        'x': region.left,
        'y': region.top,
        'width': region.width,
        'height': region.height,
      });

  static Future<void> hideRegion() => _channel.invokeMethod('hideRegion');

  static Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('hasScreenRecordingPermission') ??
      false;

  /// Triggers the system prompt (only shown once per app by macOS).
  static Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestScreenRecordingPermission') ??
      false;

  static Future<void> setAlwaysOnTop(bool value) =>
      _channel.invokeMethod('setAlwaysOnTop', value);
}
