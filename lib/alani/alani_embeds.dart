import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Converts only documented, public providers to their official embed URL.
/// Never attempts to download, rehost, strip credits or bypass restrictions.
Uri? alaniOfficialEmbed(Uri? source) {
  if (source == null || source.scheme != 'https' ||
      source.userInfo.isNotEmpty || source.host.isEmpty) return null;
  final host = source.host.toLowerCase();
  if (host == 'youtube.com' || host == 'www.youtube.com' ||
      host == 'm.youtube.com' || host == 'youtu.be') {
    String? id;
    if (host == 'youtu.be') {
      id = source.pathSegments.isEmpty ? null : source.pathSegments.first;
    } else if (source.pathSegments.isNotEmpty &&
        const ['shorts', 'embed', 'live'].contains(source.pathSegments.first) &&
        source.pathSegments.length > 1) {
      id = source.pathSegments[1];
    } else if (source.path == '/watch') {
      id = source.queryParameters['v'];
    }
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return null;
    return Uri.https('www.youtube-nocookie.com', '/embed/$id', {
      'playsinline': '1', 'rel': '0',
    });
  }
  if (host == 'tiktok.com' || host == 'www.tiktok.com' ||
      host == 'm.tiktok.com') {
    final match = RegExp(r'/video/(\d{12,24})').firstMatch(source.path);
    if (match == null) return null;
    return Uri.https('www.tiktok.com', '/player/v1/${match.group(1)}',
      {'controls': '1', 'description': '1', 'music_info': '1'});
  }
  if (host == 'facebook.com' || host == 'www.facebook.com' ||
      host == 'm.facebook.com' || host == 'fb.watch') {
    // Facebook's official embedded-video plugin retains the origin link.
    // Do not render non-video posts as videos.
    if (!source.path.contains('/videos/') &&
        !source.path.contains('/watch/') &&
        !source.path.contains('/reel/')) return null;
    return Uri.https('www.facebook.com', '/plugins/video.php', {
      'href': source.toString(), 'show_text': 'false',
      'width': '350', 'height': '600',
    });
  }
  return null;
}

/// Each vertical reel builds an embedded player only for the active page.
/// Provider playback, privacy and availability rules still apply.
class AlAniOfficialEmbeddedVideo extends StatefulWidget {
  const AlAniOfficialEmbeddedVideo({super.key, required this.uri});
  final Uri uri;

  @override
  State<AlAniOfficialEmbeddedVideo> createState() =>
      _AlAniOfficialEmbeddedVideoState();
}

class _AlAniOfficialEmbeddedVideoState extends State<AlAniOfficialEmbeddedVideo> {
  late final WebViewController _web;
  bool _loading = true;
  bool _failed = false;

  static bool _allowedDestination(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    return const {
      'www.youtube-nocookie.com', 'www.youtube.com',
      'www.tiktok.com', 'www.facebook.com',
    }.contains(host);
  }

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() { _loading = false; _failed = true; });
          }
        },
        onNavigationRequest: (request) => _allowedDestination(request.url)
          ? NavigationDecision.navigate : NavigationDecision.prevent,
      ))
      ..loadRequest(widget.uri, headers: const {
        'Referer': 'https://alani-site-admin-staging.up.railway.app/',
      });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      WebViewWidget(controller: _web),
      if (_loading) const Center(child: CircularProgressIndicator(
        color: Colors.white)),
      if (_failed) const Center(child: Text(
        'تعذّر تحميل المشغّل الرسمي لهذا الفيديو.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      )),
    ],
  );
}
