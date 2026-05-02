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

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'status':
        final args = (call.arguments as Map).cast<String, Object?>();
        peers = (args['peers'] as List).cast<String>();
        queued = args['queued'] as int;
        notifyListeners();
        return null;
      case 'approvePeer':
        final name = (call.arguments as Map)['name'] as String;
        return approvePeer(name);
    }
    return null;
  }

  /// Hands [png] to the link; it is delivered right away or once an iPad
  /// connects. Returns the slide's number.
  Future<int> send(Uint8List png) async =>
      (await _channel.invokeMethod<int>('sendSlide', png))!;
}
