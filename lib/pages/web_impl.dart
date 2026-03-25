import 'dart:html' as html;

void downloadFile(String url, String filename) {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..setAttribute('target', '_blank')
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}