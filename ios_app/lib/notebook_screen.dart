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

  // ---------------------------------------------------------------- layout

  double _pageWidthFor(double viewportWidth) =>
      math.min(viewportWidth - 2 * (_sidePadding + _band), _maxPageWidth);

  /// On-screen page width at [zoom].
  double _zoomedWidth([double? zoom]) =>
      _pageWidthFor(_viewport.width) * (zoom ?? _zoom);

  /// Width of the horizontally scrollable content at page width [w].
  double _contentWidth(double w) =>
      math.max(_viewport.width, w + 2 * (_sidePadding + _band));

  /// Top of page [index]'s list item, in list content coordinates.
  double _itemTop(int index, double w) {
    var y = _pageGap; // list top padding
    for (var i = 0; i < index; i++) {
      y += _itemExtent(_doc!.pages[i], w);
    }
    return y;
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      // Leaving goes through _close so the note is saved first. This also
      // disables the iOS edge-swipe, which would fight with drawing.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: _buildScaffold(context, doc),
    );
  }

  Widget _buildScaffold(BuildContext context, NoteDocument doc) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E9EE),
      appBar: _buildToolbar(context, doc),
      body: Stack(
        children: [
          Listener(
            // Raw pointer tracking for pinch zoom; it doesn't compete with
            // the scroll views' gestures, it just freezes them while pinching.
            onPointerDown: _onTouchDown,
            onPointerMove: _onTouchMove,
            onPointerUp: _onTouchEnd,
            onPointerCancel: _onTouchEnd,
            child: ScrollConfiguration(
              behavior: _NotebookScrollBehavior(
                fingerDraws: _settings.fingerDraws,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _viewport = constraints.biggest;
                  final width = _zoomedWidth();
                  final physics = _pinch != null
                      ? const NeverScrollableScrollPhysics()
                      : null;
                  return SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    physics: physics,
                    child: SizedBox(
                      width: _contentWidth(width),
                      height: constraints.maxHeight,
                      child: ListView.builder(
                        controller: _scroll,
                        physics: physics,
                        // Room after the last page so its bottom edge can
                        // be scrolled all the way up to the top.
                        padding: EdgeInsets.only(
                          top: _pageGap,
                          bottom: math.max(
                            0,
                            constraints.maxHeight - _band - _pageGap,
                          ),
                        ),
                        itemCount: doc.pages.length,
                        // Exact extents keep offsets stable when pages are
                        // appended and make zoom anchoring exact.
                        itemExtentBuilder: (i, _) => i < doc.pages.length
                            ? _itemExtent(doc.pages[i], width)
                            : null,
                        itemBuilder: (context, i) =>
                            _buildPage(doc.pages[i], i, width),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_zoom != 1)
            Positioned(
              left: 16,
              bottom: 16,
              child: ActionChip(
                avatar: const Icon(Icons.zoom_out_map, size: 18),
                label: Text('${(_zoom * 100).round()}%'),
                tooltip: 'Reset zoom',
                onPressed: _resetZoom,
              ),
            ),
          if (doc.pages.isEmpty)
            const Center(
              child: Text(
                'No pages yet.\nScreenshots from the Mac appear here, '
                'or add a blank page from the toolbar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 16),
              ),
            )
          else
            Positioned(
              right: 16,
              bottom: 16,
              // Purely informational; let taps reach page buttons under it.
              child: IgnorePointer(
                child: _PageIndicator(
                  current: math.min(_currentPage + 1, doc.pages.length),
                  total: doc.pages.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
