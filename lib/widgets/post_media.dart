import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/image_data.dart';

/// แสดงสื่อของโพสต์: type == 'video' -> เครื่องเล่นวิดีโอ, นอกนั้น -> รูป
/// ถ้ามี [moreUrls] (โพสต์หลายรูป) จะแสดงเป็นตารางรูป กดดูเต็มจอและปัดดูทีละรูปได้
class PostMedia extends StatelessWidget {
  final String url;
  final String? type;
  final List<String> moreUrls;
  final double errorHeight;

  const PostMedia({
    required this.url,
    this.type,
    this.moreUrls = const [],
    this.errorHeight = 150,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'video') return _VideoBox(url: url);
    if (moreUrls.isNotEmpty) {
      return PostImageGallery(urls: [url, ...moreUrls]);
    }
    return AppImage(
      src: url,
      width: double.infinity,
      fit: BoxFit.cover,
      errorHeight: errorHeight,
    );
  }
}

/// ตารางรูปของโพสต์หลายรูป: 2 รูป = เคียงกัน, 3 รูป = ใหญ่ซ้าย + เล็กสองรูปขวา,
/// 4 รูปขึ้นไป = 2x2 (ถ้ามีเกิน 4 รูปจะแสดง +N ที่ช่องสุดท้าย)
class PostImageGallery extends StatelessWidget {
  final List<String> urls;
  const PostImageGallery({required this.urls, super.key});

  static const _gap = 2.0;

  void _open(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ImageViewer(urls: urls, initialIndex: index),
      ),
    );
  }

  Widget _tile(BuildContext context, int index, {int hiddenCount = 0}) {
    return GestureDetector(
      onTap: () => _open(context, index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(src: urls[index], fit: BoxFit.cover),
          if (hiddenCount > 0)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$hiddenCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = urls.length;
    if (count == 0) return const SizedBox.shrink();
    if (count == 1) {
      return GestureDetector(
        onTap: () => _open(context, 0),
        child: AppImage(src: urls.first, width: double.infinity),
      );
    }

    final Widget grid;
    if (count == 2) {
      grid = Row(
        children: [
          Expanded(child: _tile(context, 0)),
          const SizedBox(width: _gap),
          Expanded(child: _tile(context, 1)),
        ],
      );
    } else if (count == 3) {
      grid = Row(
        children: [
          Expanded(flex: 3, child: _tile(context, 0)),
          const SizedBox(width: _gap),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(child: _tile(context, 1)),
                const SizedBox(height: _gap),
                Expanded(child: _tile(context, 2)),
              ],
            ),
          ),
        ],
      );
    } else {
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(context, 0)),
                const SizedBox(width: _gap),
                Expanded(child: _tile(context, 1)),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(context, 2)),
                const SizedBox(width: _gap),
                Expanded(child: _tile(context, 3, hiddenCount: count - 4)),
              ],
            ),
          ),
        ],
      );
    }
    return AspectRatio(aspectRatio: count == 3 ? 16 / 10 : 1.25, child: grid);
  }
}

/// ดูรูปเต็มจอ ปัดซ้าย/ขวาเพื่อเปลี่ยนรูป บีบเพื่อซูมได้
class _ImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ImageViewer({required this.urls, required this.initialIndex});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: AppImage(src: widget.urls[i], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// ตอนแรกแสดงแค่ภาพปก + ปุ่มเล่น (ยังไม่โหลดวิดีโอ)
/// พอกดถึงค่อยสร้าง VideoPlayerController — ฟีดที่มีหลายวิดีโอจะได้ไม่หนัก
class _VideoBox extends StatefulWidget {
  final String url;
  const _VideoBox({required this.url});

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;

  // Cloudinary: เปลี่ยนนามสกุลเป็น .jpg จะได้เฟรมแรกของวิดีโอเป็นภาพปก
  String get _poster =>
      widget.url.replaceFirst(RegExp(r'\.[a-zA-Z0-9]+$'), '.jpg');

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _toggle() {
    final c = _c!;
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return AspectRatio(
      // วิดีโอแนวตั้งจะสูงมาก จึงจำกัดสัดส่วนไว้ 0.75–1.78
      aspectRatio: (c?.value.aspectRatio ?? 16 / 9)
          .clamp(0.75, 1.78)
          .toDouble(),
      child: ColoredBox(
        color: Colors.black,
        child: c == null ? _cover() : _player(c),
      ),
    );
  }

  Widget _cover() {
    return GestureDetector(
      onTap: _loading ? null : _start,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _poster,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          Center(
            child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : _failed
                ? const Text(
                    'เล่นวิดีโอไม่สำเร็จ แตะเพื่อลองใหม่',
                    style: TextStyle(color: Colors.white),
                  )
                : const Icon(
                    Icons.play_circle_fill,
                    size: 64,
                    color: Colors.white,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _player(VideoPlayerController c) {
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, v, __) => v.isPlaying
                ? const SizedBox()
                : const Icon(
                    Icons.play_circle_fill,
                    size: 64,
                    color: Colors.white70,
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(c, allowScrubbing: true),
          ),
        ],
      ),
    );
  }
}
