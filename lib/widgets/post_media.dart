import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../utils/image_data.dart';

/// แสดงสื่อของโพสต์: type == 'video' -> เครื่องเล่นวิดีโอ, นอกนั้น -> รูป
class PostMedia extends StatelessWidget {
  final String url;
  final String? type;
  final double errorHeight;

  const PostMedia({
    required this.url,
    this.type,
    this.errorHeight = 150,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (type == 'video') return _VideoBox(url: url);
    return AppImage(
      src: url,
      width: double.infinity,
      fit: BoxFit.cover,
      errorHeight: errorHeight,
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
