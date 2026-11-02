import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// อีโมจิรีแอกชันที่ใช้ร่วมกันทั้งโพสต์หน้าแรก / ชุมชน / เพจ
class ReactionOption {
  final String type;
  final String emoji;
  final String label;
  const ReactionOption(this.type, this.emoji, this.label);
}

const kReactionOptions = [
  ReactionOption('like', '\u{1F44D}', 'Like'),
  ReactionOption('love', '❤️', 'Love'),
  ReactionOption('care', '\u{1F917}', 'Care'),
  ReactionOption('haha', '\u{1F602}', 'Haha'),
  ReactionOption('wow', '\u{1F62E}', 'Wow'),
  ReactionOption('sad', '\u{1F622}', 'Sad'),
  ReactionOption('angry', '\u{1F621}', 'Angry'),
];

/// ชนิด reaction ทั้งหมดที่ระบบรับ (ต้องตรงกับ firestore.rules ของชุมชน)
const kReactionTypes = [
  'like',
  'dislike',
  'love',
  'care',
  'haha',
  'wow',
  'sad',
  'angry',
];

ReactionOption? reactionOptionFor(String? type) {
  for (final option in kReactionOptions) {
    if (option.type == type) return option;
  }
  return null;
}

/// หน้าต่างเลือกอีโมจิ (กด Like ค้าง)
void showReactionPicker(BuildContext context, ValueChanged<String> onSelected) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
        child: Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kReactionOptions)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSelected(option.type);
                },
                child: SizedBox(
                  width: 58,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(height: 4),
                      Text(option.label, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// แถวสรุปจำนวนอีโมจิ (ไม่รวม Like / Dislike ซึ่งมีตัวนับแยก)
class ReactionSummary extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  const ReactionSummary({required this.stream, super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final counts = <String, int>{};
        for (final doc in snap.data!.docs) {
          final type = doc.data()['type'] as String?;
          if (type != null && type != 'like' && type != 'dislike') {
            counts[type] = (counts[type] ?? 0) + 1;
          }
        }
        final options = kReactionOptions
            .where((o) => o.type != 'like' && (counts[o.type] ?? 0) > 0)
            .toList();
        if (options.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                Text(
                  '${o.emoji} ${counts[o.type]}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// ปุ่ม Like / Dislike / Comment / Share หน้าตาเดียวกับโพสต์หน้าแรก
class PostActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? emoji;
  final VoidCallback? onLongPress;
  const PostActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.emoji,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Colors.black54;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null)
              Text(emoji!, style: const TextStyle(fontSize: 18))
            else
              Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
