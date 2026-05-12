// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Triggers a browser download (Flutter Web).
void downloadTextFile(String filename, String contents, {String mimeType = 'text/plain'}) {
  final blob = html.Blob([contents], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
