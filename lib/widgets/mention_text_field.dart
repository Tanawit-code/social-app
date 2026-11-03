import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mention_service.dart';
import '../utils/mention.dart';
import 'user_avatar.dart';

/// Controller ที่เก็บข้อความ "ตามที่เห็น" (`@ชื่อ`) คู่กับ uid ของคนที่เลือกแท็ก
/// ใช้ [encoded] ตอนบันทึก เพื่อได้ข้อความรูปแบบ `@[ชื่อ](uid)`
class MentionController extends TextEditingController {
  final Map<String, String> _picked = {}; // '@ชื่อ' -> uid

  /// [encoded] = ข้อความที่เก็บไว้แล้ว (มี token) ใช้ตอนแก้ไข
  MentionController({String? encoded}) {
    if (encoded != null) setEncoded(encoded);
  }

  void setEncoded(String stored) {
    _picked.clear();
    text = stored.replaceAllMapped(Mention.pattern, (m) {
      final shown = '@${m.group(1)}';
      _picked[shown] = m.group(2)!;
      return shown;
    });
  }

  /// บันทึกว่าเลือกแท็ก [user] แล้ว คืนข้อความที่จะแสดง (ไม่ซ้ำกับคนอื่นที่ชื่อเดียวกัน)
  String register(MentionUser user) {
    final base = user.name.replaceAll(RegExp(r'[\[\]()\n]'), '').trim();
    var shown = '@$base';
    var n = 2;
    while (_picked.containsKey(shown) && _picked[shown] != user.uid) {
      shown = '@$base $n';
      n++;
    }
    _picked[shown] = user.uid;
    return shown;
  }

  RegExp? get _picker {
    if (_picked.isEmpty) return null;
    final keys = _picked.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    // ต้องขึ้นต้นด้วยช่องว่าง/ต้นข้อความ และต่อด้วยช่องว่าง/เครื่องหมาย/จบข้อความ
    return RegExp(
      '(?<=^|\\s)(?:${keys.map(RegExp.escape).join('|')})(?=\\s|\$|[.,!?;:])',
    );
  }

  /// ข้อความพร้อมบันทึก: `@ชื่อ` ที่เลือกไว้จะกลายเป็น `@[ชื่อ](uid)`
  String get encoded {
    final re = _picker;
    if (re == null) return text;
    return text.replaceAllMapped(
      re,
      (m) => Mention.token(m[0]!.substring(1), _picked[m[0]!]!),
    );
  }

  @override
  void clear() {
    _picked.clear();
    super.clear();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final re = _picker;
    final composing = withComposing && value.composing.isValid && !value.composing.isCollapsed;
    if (re == null || composing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(
        TextSpan(
          text: m[0],
          style: const TextStyle(
            color: Color(0xFF1E88E5),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: spans);
  }
}

/// สร้าง [MentionController] ให้ dialog / bottom sheet และ dispose ตามวงจรชีวิตของ widget
class MentionControllerScope extends StatefulWidget {
  final String encoded;
  final Widget Function(BuildContext context, MentionController controller)
  builder;
  const MentionControllerScope({
    this.encoded = '',
    required this.builder,
    super.key,
  });

  @override
  State<MentionControllerScope> createState() => _MentionControllerScopeState();
}

class _MentionControllerScopeState extends State<MentionControllerScope> {
  late final MentionController _controller = MentionController(
    encoded: widget.encoded,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

/// ช่องพิมพ์ข้อความที่พิมพ์ `@` แล้วแนะนำชื่อผู้ใช้ให้เลือกแท็กได้
/// รายชื่อที่แนะนำขึ้นกับ [scope] (ใครมีสิทธิ์ถูกแท็กในที่นั้น)
class MentionTextField extends StatefulWidget {
  final MentionController controller;
  final MentionScope scope;
  final InputDecoration decoration;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;

  /// true = แสดงรายชื่อเหนือช่องพิมพ์ (เหมาะกับช่องคอมเมนต์ที่อยู่ล่างจอ)
  final bool suggestionsAbove;
  final FocusNode? focusNode;

  const MentionTextField({
    required this.controller,
    required this.scope,
    this.decoration = const InputDecoration(),
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.suggestionsAbove = false,
    this.focusNode,
    super.key,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  static final _active = RegExp(r'(?:^|\s)@([^\s@]{0,30})$');
  List<MentionUser> _results = const [];
  int _tokenStart = -1;
  String? _query;
  Timer? _debounce;
  int _seq = 0;
  // key คงที่ เพื่อให้ TextField ไม่ถูกสร้างใหม่ (เสียโฟกัส) ตอนรายชื่อแนะนำโผล่/หาย
  final _fieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant MentionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    if (!widget.scope.enabled && _results.isNotEmpty) _reset();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _reset() {
    _debounce?.cancel();
    _seq++;
    _query = null;
    _tokenStart = -1;
    if (_results.isNotEmpty && mounted) setState(() => _results = const []);
  }

  void _onChanged() {
    final c = widget.controller;
    final sel = c.selection;
    if (!widget.scope.enabled || !sel.isValid || !sel.isCollapsed) {
      _reset();
      return;
    }
    final cursor = sel.baseOffset;
    if (cursor < 0 || cursor > c.text.length) {
      _reset();
      return;
    }
    final m = _active.firstMatch(c.text.substring(0, cursor));
    if (m == null) {
      _reset();
      return;
    }
    final q = m.group(1)!;
    _tokenStart = cursor - q.length - 1;
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      final seq = ++_seq;
      List<MentionUser> found;
      try {
        found = await widget.scope.search(q);
      } catch (_) {
        found = const [];
      }
      if (!mounted || seq != _seq) return;
      setState(() => _results = found);
    });
  }

  void _pick(MentionUser user) {
    final c = widget.controller;
    final cursor = c.selection.baseOffset;
    final start = _tokenStart;
    if (start < 0 || cursor < start || cursor > c.text.length) return;
    final shown = '${c.register(user)} ';
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, cursor, shown),
      selection: TextSelection.collapsed(offset: start + shown.length),
    );
    _reset();
  }

  Widget _suggestions() => Material(
    elevation: 3,
    borderRadius: BorderRadius.circular(10),
    color: Theme.of(context).colorScheme.surface,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      // ใช้ Column ใน SingleChildScrollView (ไม่ใช้ ListView) เพื่อให้ใช้ใน AlertDialog ได้
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final u in _results)
              ListTile(
                dense: true,
                leading: UserAvatar(uid: u.uid, radius: 14),
                title: Text(
                  u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _pick(u),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      decoration: widget.decoration,
    );
    final list = _results.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _suggestions(),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.suggestionsAbove && list != null) list,
        field,
        if (!widget.suggestionsAbove && list != null) list,
      ],
    );
  }
}
