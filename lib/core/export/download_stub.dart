/// Non-web platforms — CSV export not supported here.
void downloadTextFile(String filename, String contents, {String mimeType = 'text/plain'}) {
  throw UnsupportedError('downloadTextFile is only supported on web in this project.');
}
