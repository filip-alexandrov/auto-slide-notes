import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screen_capture.dart';
import 'slide_link.dart';

const _kRegion = 'region';
const _kOnTop = 'alwaysOnTop';
const _kHotKey = 'hotKey';
const _kHotKeyEnabled = 'hotKeyEnabled';

void main() {
  runApp(const MacCaptureApp());
}

class MacCaptureApp extends StatelessWidget {
  const MacCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slide Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E5EFF)),
        useMaterial3: true,
      ),
      home: const CaptureScreen(),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}
