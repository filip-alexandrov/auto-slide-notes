import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'page_canvas.dart' show paintStroke;

/// Persists one note as `document.json` plus slide images in its folder.
class DocumentStore {
  DocumentStore._(this.root);

  final Directory root;

  String get id => _basename(root);
  Directory get imagesDir => Directory('${root.path}/images');
  File get _docFile => File('${root.path}/document.json');
  File get _metaFile => File('${root.path}/meta.json');
  File get _thumbFile => File('${root.path}/thumbnail.png');
}
