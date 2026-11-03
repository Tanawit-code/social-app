import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../screens/profile_screen.dart';
import '../utils/mention.dart';

/// แสดงข้อความที่มีการแท็ก `@[ชื่อ](uid)` — ชื่อที่ถูกแท็กเป็นสีน้ำเงินและกดเปิดโปรไฟล์ได้
class MentionText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final Color? mentionColor;

  const MentionText(
    this.text, {
    this.style,
    this.maxLines,
    this.overflow,
    this.mentionColor,
    super.key,
  });

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _openProfile(String uid) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)),
  );

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final matches = Mention.pattern.allMatches(widget.text).toList();
    if (matches.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    final color = widget.mentionColor ?? const Color(0xFF1E88E5);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final uid = m.group(2)!;
      final recognizer = TapGestureRecognizer()..onTap = () => _openProfile(uid);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: '@${m.group(1)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
