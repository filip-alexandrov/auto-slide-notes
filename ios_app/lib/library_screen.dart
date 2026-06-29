import 'package:flutter/material.dart';

import 'document_store.dart';
import 'notebook_screen.dart';

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
