import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveFile(Uint8List bytes, String fileName) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    debugPrint('[FileSaver] Saved: ${file.path}');
  } catch (e) {
    debugPrint('[FileSaver] Error: $e');
    rethrow;
  }
}
