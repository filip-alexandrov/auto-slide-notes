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
}
