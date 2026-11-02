import 'package:flutter/material.dart';

/// สร้าง TextEditingController ให้ dialog / bottom sheet และ dispose ตามวงจรชีวิตของ widget
/// (ไม่ dispose ทันทีหลัง await showDialog ซึ่ง TextField ยังอยู่ใน animation ปิด)
class TextControllerScope extends StatefulWidget {
  final String text;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;
  const TextControllerScope({this.text = '', required this.builder, super.key});
  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
