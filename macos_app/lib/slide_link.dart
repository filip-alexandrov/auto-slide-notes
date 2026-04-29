import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the Multipeer link to nearby iPads
/// (see `SlideLinkHost` in macos/Runner/MainFlutterWindow.swift).
class SlideLink extends ChangeNotifier {
  SlideLink({required this.approvePeer}) {
    _channel.setMethodCallHandler(_handle);
    _channel.invokeMethod('status');
  }

  static const _channel = MethodChannel('mac_capture/link');

  /// Asked when an iPad connects for the first time; true trusts it.
  final Future<bool> Function(String name) approvePeer;

  /// Names of the iPads currently connected.
  List<String> peers = const [];

  /// Slides waiting for an iPad to connect.
  int queued = 0;
}
