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
}
