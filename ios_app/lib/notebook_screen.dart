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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pencilChannel.setMethodCallHandler(null);
    _link?.dispose();
    _saver?.flush();
    _saver?.dispose();
    _scroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iPadOS drops peer-to-peer links in the background; reconnect on return.
    if (state == AppLifecycleState.resumed) {
      _link?.start();
    } else if (state == AppLifecycleState.paused) {
      _link?.stop();
      _saver?.flush(thumbnail: true);
    } else if (state == AppLifecycleState.inactive) {
      _saver?.flush();
    }
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

  void _addBlankPage() {
    final doc = _doc!;
    doc.appendPage(NotePage(id: DocumentStore.newPageId(), aspect: 1));
    setState(() {});
    _jumpToPage(doc.pages.length - 1);
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

  Widget _buildPage(NotePage page, int index, double width) {
    Widget extend(PageSide side) => _ResizeButtons(
      side: side,
      onGrow: () => _resizePage(page, side, grow: true),
      onShrink: page.removableOn(side) > 0
          ? () => _resizePage(page, side, grow: false)
          : null,
    );

    return SizedBox(
      height: _itemExtent(page, width),
      child: Column(
        children: [
          // Buttons are pinned to the page's top-left corner area so they
          // don't move when the page is resized.
          SizedBox(
            height: _band,
            width: width,
            child: Align(
              alignment: Alignment.centerLeft,
              child: extend(PageSide.top),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _band,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: extend(PageSide.left),
                ),
              ),
              Material(
                elevation: 2,
                child: SizedBox(
                  width: width,
                  child: PageCanvas(
                    key: ValueKey(page.id),
                    page: page,
                    imageFile: page.imageFile == null
                        ? null
                        : _store!.imageFile(page.imageFile!),
                    settings: _settings,
                    onStrokeAdded: (p, s) => _recordEdit(_Edit.add(p, [s])),
                    onStrokesErased: (p, s) => _recordEdit(_Edit.erase(p, s)),
                  ),
                ),
              ),
              SizedBox(
                width: _band,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: extend(PageSide.right),
                ),
              ),
            ],
          ),
          SizedBox(
            height: _band,
            width: width,
            child: Row(
              children: [
                extend(PageSide.bottom),
                const SizedBox(width: 20),
                _DeleteButton(
                  tooltip: page.slideId != null
                      ? 'Delete slide'
                      : 'Delete page',
                  onPressed: () => _deletePage(page),
                ),
                const Spacer(),
                Text(
                  page.slideId != null
                      ? '${index + 1} · slide'
                      : '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildToolbar(BuildContext context, NoteDocument doc) {
    final s = _settings;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final singleRow = windowWidth >= _singleRowMinWidth;
    // Slide Over and similar: document actions join the tool row.
    final compact = windowWidth < _compactMaxWidth;

    Widget toolButton(DrawTool tool, IconData icon, String tip) => IconButton(
      tooltip: tip,
      isSelected: s.tool == tool,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: s.tool == tool ? Colors.black12 : null,
      ),
      onPressed: () => setState(() => _settings = s.copyWith(tool: tool)),
    );

    final docActions = IconTheme.merge(
      data: const IconThemeData(color: Colors.black87),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
            onPressed: _undo.isEmpty ? null : _applyUndo,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
            onPressed: _redo.isEmpty ? null : _applyRedo,
          ),
          IconButton(
            tooltip: 'Add blank page',
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _addBlankPage,
          ),
          Builder(
            builder: (btnContext) => IconButton(
              tooltip: 'Export PDF',
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _exporting ? null : () => _exportPdf(btnContext),
            ),
          ),
        ],
      ),
    );

    // Groups are spread evenly over all the width they get. Only in very
    // narrow windows (Slide Over) is the row scaled down to fit.
    final drawingToolsRow = IconTheme.merge(
      data: const IconThemeData(color: Colors.black87),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toolButton(DrawTool.pen, Icons.edit, 'Pen'),
              toolButton(
                DrawTool.highlighter,
                Icons.border_color,
                'Highlighter',
              ),
              toolButton(DrawTool.eraser, Icons.auto_fix_normal, 'Eraser'),
            ],
          ),
          // Colors and widths belong to the highlighter while it is selected,
          // otherwise to the pen (picking one from the eraser switches to pen).
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in s.isHighlighter ? _highlighterColors : _penColors)
                _ColorSwatch(
                  color: c,
                  selected:
                      c == (s.isHighlighter ? s.highlighterColor : s.penColor),
                  onTap: () => setState(
                    () => _settings = s.isHighlighter
                        ? s.copyWith(highlighterColor: c)
                        : s.copyWith(penColor: c, tool: DrawTool.pen),
                  ),
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (w, dot)
                  in s.isHighlighter ? _highlighterWidths : _penWidths)
                _WidthButton(
                  dot: dot,
                  color: s.isHighlighter ? s.highlighterColor : 0xDD000000,
                  selected:
                      w == (s.isHighlighter ? s.highlighterWidth : s.penWidth),
                  onTap: () => setState(
                    () => _settings = s.isHighlighter
                        ? s.copyWith(highlighterWidth: w)
                        : s.copyWith(penWidth: w),
                  ),
                ),
            ],
          ),
          PopupMenuButton<Smoothing>(
            tooltip: 'Smoothing: ${s.smoothing.label}',
            initialValue: s.smoothing,
            onSelected: (level) {
              setState(() => _settings = _settings.copyWith(smoothing: level));
              _prefs?.setString(_smoothingKey, level.name);
            },
            itemBuilder: (_) => [
              for (final level in Smoothing.values)
                CheckedPopupMenuItem(
                  value: level,
                  checked: level == s.smoothing,
                  child: Text('${level.label} smoothing'),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gesture, size: 22),
                  Text(
                    s.smoothing.label,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          if (compact) docActions,
        ],
      ),
    );

    final drawingTools = LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: drawingToolsRow,
        ),
      ),
    );

    final title = InkWell(
      onTap: _rename,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: singleRow ? 220 : 400),
          child: Text(doc.title, overflow: TextOverflow.ellipsis),
        ),
      ),
    );

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 1,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          if (compact)
            IconButton(
              tooltip: 'Notes',
              onPressed: _closing ? null : _close,
              icon: const Icon(Icons.grid_view_rounded, size: 20),
            )
          else
            TextButton.icon(
              onPressed: _closing ? null : _close,
              icon: const Icon(Icons.grid_view_rounded, size: 20),
              label: const Text('Notes'),
            ),
          const SizedBox(width: 4),
          _StatusDot(link: _link!),
          const SizedBox(width: 8),
          // Tap the title to rename the note. With the tools in the same
          // row its width is capped so the tools always get their space;
          // otherwise it takes what is left next to the actions.
          if (singleRow) title else Flexible(child: title),
          if (singleRow) ...[
            const SizedBox(width: 12),
            Expanded(child: drawingTools),
          ],
        ],
      ),
      actions: [
        if (singleRow) const VerticalDivider(indent: 12, endIndent: 12),
        if (!compact) docActions,
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'finger':
                setState(
                  () => _settings = s.copyWith(fingerDraws: !s.fingerDraws),
                );
              case 'rename':
                _rename();
              case 'bin':
                _openRecycleBin();
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: 'finger',
              checked: s.fingerDraws,
              child: const Text('Draw with finger'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'bin',
              child: Text(
                doc.trash.isEmpty
                    ? 'Recycle bin'
                    : 'Recycle bin (${doc.trash.length})',
              ),
            ),
            const PopupMenuItem(value: 'rename', child: Text('Rename…')),
          ],
        ),
        const SizedBox(width: 4),
      ],
      // Narrower windows (e.g. portrait) give the drawing tools their own
      // full-width row so nothing has to scroll or get cut off.
      bottom: singleRow
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(_toolRowHeight),
              child: Container(
                height: _toolRowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x14000000))),
                ),
                child: drawingTools,
              ),
            ),
    );
  }
}

/// An undoable change on one page.
class _Edit {
  _Edit._(this.apply, this.revert, {this.deletedPage});

  _Edit.add(NotePage page, List<Stroke> strokes)
    : this._(
        () => page.insertStrokes(strokes),
        () => page.removeStrokes(strokes),
      );

  _Edit.erase(NotePage page, List<Stroke> strokes)
    : this._(
        () => page.removeStrokes(strokes),
        () => page.insertStrokes(strokes),
      );

  final VoidCallback apply;
  final VoidCallback revert;
  final NotePage? deletedPage;
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black : Colors.black26,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _WidthButton extends StatelessWidget {
  const _WidthButton({
    required this.dot,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final double dot;
  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.black12 : null,
        ),
        alignment: Alignment.center,
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
