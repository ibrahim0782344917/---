import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Inline player for directly hosted HTTPS videos. YouTube/web page links
/// remain external rather than passing a webpage URL to a media decoder.
bool isDirectMediaUrl(Uri? uri) {
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
  final path = uri.path.toLowerCase();
  return path.endsWith('.mp4') ||
      path.endsWith('.m3u8') ||
      path.endsWith('.mov') ||
      path.endsWith('.m4v');
}

class AlAniVideoPage extends StatefulWidget {
  final String title;
  final Uri url;

  const AlAniVideoPage({super.key, required this.title, required this.url});

  @override
  State<AlAniVideoPage> createState() => _AlAniVideoPageState();
}

class _AlAniVideoPageState extends State<AlAniVideoPage>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(widget.url);
    _controller.addListener(_updated);
    _initialization = _controller.initialize();
  }

  void _updated() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _controller.value.isInitialized) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_updated);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Center(
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          if (snapshot.hasError || _controller.value.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذّر تشغيل الفيديو داخل التطبيق.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(widget.url,
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('فتح الفيديو خارج التطبيق'),
                  ),
                ],
              ),
            );
          }
          final videoValue = _controller.value;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: videoValue.aspectRatio > 0
                      ? videoValue.aspectRatio : 16 / 9,
                  child: VideoPlayer(_controller),
                ),
                VideoProgressIndicator(
                  _controller, allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                IconButton.filledTonal(
                  tooltip: videoValue.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
                  onPressed: () {
                    if (videoValue.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  },
                  icon: Icon(videoValue.isPlaying
                      ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  iconSize: 34,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
