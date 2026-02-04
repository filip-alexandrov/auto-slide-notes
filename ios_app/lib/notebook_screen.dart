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
