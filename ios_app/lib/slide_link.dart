import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'document_store.dart';
import 'models.dart';

enum LinkState { off, searching, connecting, connected }

/// Receives slides pushed by the Mac app over Multipeer Connectivity
/// (see `SlideLinkClient` in ios/Runner/AppDelegate.swift) and appends each
/// one as a new page of the open note.
class SlideLink extends ChangeNotifier {
  SlideLink({
    required this.store,
    required this.doc,
    required this.onSlideAdded,
  });

  static const _channel = MethodChannel('ipad_notes/link');

  final DocumentStore store;
  final NoteDocument doc;
  final void Function(NotePage page) onSlideAdded;

  LinkState state = LinkState.off;

  /// Name of the Mac connected (or being connected) to.
  String? peer;

  /// Slides are imported one after another so pages keep the Mac's order.
  Future<void> _imports = Future.value();

  Future<void> start() async {
    _channel.setMethodCallHandler(_handle);
    if (state == LinkState.off) _set(LinkState.searching, null);
    try {
      await _channel.invokeMethod('start');
    } on MissingPluginException {
      // No native side (tests); stay "searching".
    }
  }

  Future<void> stop() async {
    _set(LinkState.off, null);
    try {
      await _channel.invokeMethod('stop');
    } on MissingPluginException {
      // No native side (tests).
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    switch (call.method) {
      case 'status':
        if (state == LinkState.off) return null;
        _set(
          LinkState.values.byName(args['state'] as String),
          args['peer'] as String?,
        );
      case 'slide':
        final bytes = args['bytes'] as Uint8List;
        final seq = args['seq'] as int;
        _imports = _imports.then((_) => _importSlide(bytes, seq));
    }
    return null;
  }
}
