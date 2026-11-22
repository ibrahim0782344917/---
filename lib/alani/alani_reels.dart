import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Vertical, one-at-a-time media feed for published store videos.
class AlAniReelsPanel extends StatefulWidget {
  final Future<List<AlAniPublication>> publications;
  final Future<void> Function() onRefresh;
  final bool visible;

  const AlAniReelsPanel({
    super.key,
    required this.publications,
    required this.onRefresh,
    this.visible = true,
  });

  @override
  State<AlAniReelsPanel> createState() => _AlAniReelsPanelState();
}

class _AlAniReelsPanelState extends State<AlAniReelsPanel> {
  int _active = 0;

  @override
  void didUpdateWidget(covariant AlAniReelsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publications != widget.publications) _active = 0;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AlAniPublication>>(
    future: widget.publications,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذّر تحميل الفيديوهات. تحقق من اتصال الإنترنت.'),
            TextButton(onPressed: widget.onRefresh,
              child: const Text('إعادة المحاولة')),
          ],
        ));
      }
      final videos = (snapshot.data ?? [])
          .where((item) => item.kind == 'video' &&
            (item.videoUrl ?? '').isNotEmpty).toList();
      if (videos.isEmpty) {
        return Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('لا توجد ريلز منشورة حتى الآن.'),
            TextButton(onPressed: widget.onRefresh,
              child: const Text('تحديث')),
          ],
        ));
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
          child: Row(children: [
            const Expanded(child: Text('ريلز السيد إبراهيم العاني',
              style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'تحديث الريلز',
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ]),
        ),
        Expanded(child: PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: videos.length,
          onPageChanged: (next) => setState(() => _active = next),
          itemBuilder: (context, index) => AlAniReelTile(
            key: ValueKey(videos[index].id),
            publication: videos[index],
            active: widget.visible && _active == index,
          ),
        )),
      ]);
    },
  );
}

class AlAniReelTile extends StatefulWidget {
  final AlAniPublication publication;
  final bool active;

  const AlAniReelTile({
    super.key,
    required this.publication,
    required this.active,
  });

  @override
  State<AlAniReelTile> createState() => _AlAniReelTileState();
}

class _AlAniReelTileState extends State<AlAniReelTile>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  Future<void> _start() async {
    final url = Uri.tryParse(widget.publication.videoUrl ?? '');
    if (!isDirectMediaUrl(url)) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (_controller != null) {
      await _controller!.play();
      if (mounted) setState(() {});
      return;
    }
    setState(() { _loading = true; _failed = false; });
    final player = VideoPlayerController.networkUrl(url!);
    _controller = player;
    try {
      await player.initialize();
      await player.setLooping(true);
      if (widget.active && mounted) await player.play();
    } catch (_) {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant AlAniReelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _start();
    } else if (!widget.active && oldWidget.active) {
      _controller?.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = _controller;
    if (player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = _controller;
    final ready = player?.value.isInitialized == true && !_failed;
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (ready)
          GestureDetector(
            onTap: _toggle,
            child: ClipRect(child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: player!.value.size.width,
                height: player.value.size.height,
                child: VideoPlayer(player),
              ),
            )),
          ),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (_failed)
          Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تعذّر تشغيل الريل هنا.',
                style: TextStyle(color: Colors.white)),
              TextButton(
                onPressed: () async {
                  final url = Uri.tryParse(widget.publication.videoUrl ?? '');
                  if (url != null && url.scheme == 'https') {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('فتح الفيديو خارج التطبيق'),
              ),
            ],
          )),
        if (ready && !player!.value.isPlaying)
          Center(child: IgnorePointer(child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white.withValues(alpha: 0.75),
            size: 72,
          ))),
        PositionedDirectional(
          start: 14, end: 14, bottom: 32,
          child: IgnorePointer(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.publication.title,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
              const SizedBox(height: 6),
              Text(widget.publication.body,
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
            ],
          )),
        ),
        if (ready)
          PositionedDirectional(
            start: 8, end: 8, bottom: 4,
            child: VideoProgressIndicator(
              player!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.greenAccent),
            ),
          ),
      ]),
    );
  }
}
