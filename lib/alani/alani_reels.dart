import 'package:flutter/material.dart';
import 'package:shitreed_customer/alani/alani_premium_widgets.dart';
import 'package:shitreed_customer/alani/alani_social.dart';
import 'package:shitreed_customer/alani/alani_content.dart';
import 'package:shitreed_customer/alani/alani_video.dart';
import 'package:shitreed_customer/alani/alani_embeds.dart';
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
        return Center(child: Padding(padding:const EdgeInsets.all(20),
          child:AlAniEmptyState(icon:Icons.video_library_outlined,
            message:'لا توجد ريلز منشورة حتى الآن.',
            action:TextButton(onPressed:widget.onRefresh,child:const Text('تحديث')))));
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
          child: Row(children: [
            const Expanded(child: AlAniSectionTitle('ريلز السيد إبراهيم العاني',icon:Icons.play_circle_outline)),
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
  bool _external = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _start();
  }

  Future<void> _start() async {
    if (_loading || !mounted) return;
    final url = Uri.tryParse(widget.publication.videoUrl ?? '');
    if (!isDirectMediaUrl(url)) {
      // TikTok/YouTube page URLs cannot be decoded by video_player.
      // Show a real external link instead of a misleading playback error.
      final externalLink = url != null && url.scheme == 'https' &&
          url.host.isNotEmpty;
      setState(() { _external = externalLink; _failed = !externalLink; });
      return;
    }
    if (_controller != null && _controller!.value.isInitialized) {
      if (widget.active) await _controller!.play();
      if (mounted) setState(() {});
      return;
    }
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    setState(() { _loading = true; _failed = false; _external = false; });
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

  Future<void> _openExternal() async {
    final url = Uri.tryParse(widget.publication.videoUrl ?? '');
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return;
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر فتح الفيديو الخارجي.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر فتح رابط الفيديو.')));
      }
    }
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
    final officialEmbed = alaniOfficialEmbed(
      Uri.tryParse(widget.publication.videoUrl ?? ''));
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
        if (_external && officialEmbed != null && widget.active)
          Positioned.fill(child: AlAniOfficialEmbeddedVideo(
            uri: officialEmbed)),
        if (_external && (officialEmbed == null || !widget.active))
          Center(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.open_in_new, color: Colors.white, size: 52),
              const SizedBox(height: 12),
              Text(officialEmbed == null
                ? 'هذا المقطع منشور على منصة خارجية.'
                : 'اسحب للأعلى للعودة إلى المشغّل الرسمي.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17)),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openExternal,
                icon: const Icon(Icons.play_arrow),
                label: const Text('فتح الفيديو خارج التطبيق')),
            ]),
          )),
        if (_failed)
          Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تعذّر تشغيل الريل هنا.',
                style: TextStyle(color: Colors.white)),
              TextButton(
                onPressed: _openExternal,
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
        PositionedDirectional(end: 8, bottom: 120,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xB317372B),
                borderRadius: BorderRadius.circular(22)),
              child: AlAniSocialActions(
                publicationId: widget.publication.id, dark: true,
                vertical: true),
            ),
          ),
        ),
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
                playedColor: Color(0xFFDFCA92)),
            ),
          ),
      ]),
    );
  }
}
