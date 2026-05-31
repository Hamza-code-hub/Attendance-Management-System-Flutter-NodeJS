// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveFile(Uint8List bytes, String fileName) async {
  final blob = html.Blob([bytes]);
  final url  = html.Url.createObjectUrlFromBlob(blob);
  (html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click());
  html.Url.revokeObjectUrl(url);
}
