import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'document_store.dart';
import 'ink.dart';
import 'library_screen.dart' show showRenameDialog;
import 'models.dart';
import 'page_canvas.dart';
import 'pdf_export.dart';
import 'slide_link.dart';

const double _maxPageWidth = 1000;
const double _sidePadding = 8;
const double _pageGap = 12;

/// Space around each page that holds its "extend" buttons.
const double _band = 34;

const _penColors = <int>[
  0xFF1A1A1A, // black
  0xFF1E5EFF, // blue
  0xFFE53935, // red
  0xFF2E7D32, // green
  0xFF8E24AA, // purple
];

/// Width choices (page units) and the dot size shown for each.
const _penWidths = <(double, double)>[(2, 5), (3, 8), (6, 13)];
const _highlighterWidths = <(double, double)>[(12, 6), (18, 10), (28, 15)];

/// Editor for one note of the [library].
class NotebookScreen extends StatefulWidget {
  const NotebookScreen({
    super.key,
    required this.library,
    required this.noteId,
  });

  final NoteLibrary library;
  final String noteId;

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen>
    with WidgetsBindingObserver {
  DocumentStore? _store;
  NoteDocument? _doc;
  AutoSaver? _saver;
  SlideLink? _link;
  SharedPreferences? _prefs;

  final _scroll = ScrollController();
  ToolSettings _settings = const ToolSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_updateCurrentPage);
    _pencilChannel.setMethodCallHandler((call) async {
      if (call.method == 'doubleTap') _togglePenEraser();
    });
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final store = widget.library.storeFor(widget.noteId);
    final doc = await store.load();
    widget.library.lastOpenedId = widget.noteId;
    final link = SlideLink(store: store, doc: doc, onSlideAdded: _onSlideAdded)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    if (!mounted) return;
    final smoothing = Smoothing.values
        .asNameMap()[prefs.getString(_smoothingKey)];
    setState(() {
      _prefs = prefs;
      if (smoothing != null) {
        _settings = _settings.copyWith(smoothing: smoothing);
      }
      _store = store;
      _doc = doc;
      _saver = AutoSaver(store, doc);
      _link = link;
    });
    link.start();
  }
}
