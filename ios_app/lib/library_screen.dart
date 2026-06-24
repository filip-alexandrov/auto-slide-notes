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
}
