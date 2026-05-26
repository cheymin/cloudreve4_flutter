import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AnnouncementDialog extends StatefulWidget {
  final String title;
  final String html;
  final String baseUrl;

  const AnnouncementDialog({
    super.key,
    required this.title,
    required this.html,
    required this.baseUrl,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String html,
    required String baseUrl,
  }) async {
    if (html.trim().isEmpty) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AnnouncementDialog(
        title: title,
        html: html,
        baseUrl: baseUrl,
      ),
    );
  }

  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      );

    _load();
  }

  Future<void> _load() async {
    final origin = Uri.parse(widget.baseUrl).origin;
    final html = _wrapHtml(widget.html);

    await _controller.loadHtmlString(
      html,
      baseUrl: '$origin/',
    );
  }

  String _wrapHtml(String body) {
    final encodedTitle = const HtmlEscape().convert(widget.title);

    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>$encodedTitle</title>
<style>
  html, body {
    margin: 0;
    padding: 0;
    background: transparent;
    color: #1f2937;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans SC", sans-serif;
    font-size: 14px;
    line-height: 1.65;
    overflow-wrap: anywhere;
  }
  body {
    padding: 12px 14px 18px;
    box-sizing: border-box;
  }
  img, video {
    max-width: 100% !important;
    height: auto !important;
    border-radius: 12px;
  }
  a {
    color: #2563eb;
    text-decoration: none;
  }
  fieldset, section, div {
    max-width: 100% !important;
    box-sizing: border-box !important;
  }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_loading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
