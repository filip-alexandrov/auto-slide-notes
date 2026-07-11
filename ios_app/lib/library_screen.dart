import 'package:flutter/material.dart';

import 'document_store.dart';
import 'notebook_screen.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _formatRelative(DateTime d) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final time =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Today $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
  return _formatDate(d);
}

/// Asks for a note title; returns null when cancelled or left empty.
Future<String?> showRenameDialog(
  BuildContext context,
  String current, {
  String title = 'Rename note',
}) async {
  final controller = TextEditingController(text: current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Home screen: every locally stored note as a card with a preview of its
/// first page, Notability style. Tapping a card opens the note.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  NoteLibrary? _library;
  List<NoteSummary> _notes = [];
  _SortOrder _sort = _SortOrder.modified;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final library = await NoteLibrary.open();
    final notes = await library.list();
    if (!mounted) return;
    setState(() {
      _library = library;
      _notes = notes;
    });
    // Come back to the note that was open when the app was last closed,
    // so slides from the Mac keep landing in it.
    final last = library.lastOpenedId;
    if (last != null) _open(last);
  }

  Future<void> _reload() async {
    final notes = await _library!.list();
    if (mounted) setState(() => _notes = notes);
  }

  List<NoteSummary> get _visible {
    final q = _query.toLowerCase();
    final list = [
      for (final n in _notes)
        if (q.isEmpty || n.title.toLowerCase().contains(q)) n,
    ];
    switch (_sort) {
      case _SortOrder.modified:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case _SortOrder.created:
        list.sort((a, b) => b.created.compareTo(a.created));
      case _SortOrder.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return list;
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotebookScreen(library: _library!, noteId: id),
      ),
    );
    await _reload();
  }

  Future<void> _createNote() async {
    final id = await _library!.create('Note ${_formatDate(DateTime.now())}');
    await _open(id);
  }

  Future<void> _rename(NoteSummary note) async {
    final title = await showRenameDialog(context, note.title);
    if (title == null || title == note.title) return;
    await _library!.rename(note.id, title);
    await _reload();
  }

  Future<void> _duplicate(NoteSummary note) async {
    await _library!.duplicate(note.id, '${note.title} copy');
    await _reload();
  }

  Future<void> _delete(NoteSummary note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${note.title}”?'),
        content: const Text(
          'All pages and annotations of this note will be deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _library!.delete(note.id);
    await _reload();
  }

  Future<void> _showNoteMenu(NoteSummary note, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename'),
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: ListTile(
            leading: Icon(Icons.copy_outlined),
            title: Text('Duplicate'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
    switch (action) {
      case 'rename':
        await _rename(note);
      case 'duplicate':
        await _duplicate(note);
      case 'delete':
        await _delete(note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final notes = _visible;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F7),
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        titleSpacing: 28,
        title: const Text(
          'All Notes',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
        ),
        actions: [
          SizedBox(
            width: 280,
            height: 40,
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                filled: true,
                fillColor: const Color(0x14000000),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_SortOrder>(
            tooltip: 'Sort by',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final o in _SortOrder.values)
                CheckedPopupMenuItem(
                  value: o,
                  checked: o == _sort,
                  child: Text(o.label),
                ),
            ],
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: library == null ? null : _createNote,
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
          ),
          const SizedBox(width: 24),
        ],
      ),
      body: library == null
          ? const Center(child: CircularProgressIndicator())
          : notes.isEmpty
          ? _EmptyState(searching: _query.isNotEmpty, onCreate: _createNote)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisSpacing: 28,
                crossAxisSpacing: 28,
                // Preview area plus room for title and date.
                childAspectRatio: 0.8,
              ),
              itemCount: notes.length,
              itemBuilder: (context, i) {
                final note = notes[i];
                return _NoteCard(
                  key: ValueKey(note.id),
                  note: note,
                  onTap: () => _open(note.id),
                  onMenu: (pos) => _showNoteMenu(note, pos),
                );
              },
            ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onMenu,
  });

  final NoteSummary note;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    final thumb = note.thumbnail;
    final pages = note.pageCount == 1 ? '1 page' : '${note.pageCount} pages';
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (d) => onMenu(d.globalPosition),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The first slide at its own shape, bottom-aligned so titles
          // line up across a row.
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AspectRatio(
                aspectRatio: note.thumbnailAspect ?? 3 / 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x1A000000)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: thumb != null
                        ? Image.memory(
                            thumb,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Center(
                            child: Icon(
                              note.pageCount == 0
                                  ? Icons.note_alt_outlined
                                  : Icons.description_outlined,
                              size: 40,
                              color: Colors.black26,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  note.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Title dropdown, like Notability's note options.
              Builder(
                builder: (ctx) => InkResponse(
                  radius: 16,
                  onTap: () {
                    final box = ctx.findRenderObject() as RenderBox;
                    onMenu(box.localToGlobal(box.size.bottomLeft(Offset.zero)));
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      semanticLabel: 'Note options',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_formatRelative(note.modified)} · $pages',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching, required this.onCreate});

  final bool searching;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(
        child: Text(
          'No notes match your search.',
          style: TextStyle(color: Colors.black45, fontSize: 16),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.note_alt_outlined, size: 64, color: Colors.black26),
          const SizedBox(height: 12),
          const Text(
            'No notes yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a note, then take screenshots on the Mac\n'
            'to add them as pages.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('New Note'),
          ),
        ],
      ),
    );
  }
}
