import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/event_model.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../widgets/user_avatar.dart';

class EventDetailScreen extends StatelessWidget {
  final SocialEvent event;
  const EventDetailScreen({required this.event, super.key});

  Future<void> _respond(
    BuildContext context,
    String uid,
    String? current,
    String next,
  ) async {
    try {
      await EventService().setResponse(
        eventId: event.id,
        uid: uid,
        status: current == next ? null : next,
      );
    } catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกการตอบรับไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUser?.uid ?? '';
    final service = EventService();
    final eventRef = FirebaseFirestore.instance
        .collection('events')
        .doc(event.id);
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดกิจกรรม'),
        actions: [
          if (event.hostId == uid)
            IconButton(
              tooltip: 'ลบกิจกรรม',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('ลบกิจกรรมนี้?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('ลบ'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await service.delete(event.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: eventRef.collection('responses').doc(uid).snapshots(),
        builder: (context, responseSnap) {
          final current = responseSnap.data?.data()?['status'] as String?;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Icon(Icons.event, size: 64, color: Color(0xFF6750A4)),
              const SizedBox(height: 12),
              Text(
                event.name,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (event.isCancelled)
                const Card(
                  color: Color(0xFFFFE0E0),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('กิจกรรมนี้ถูกยกเลิกแล้ว'),
                  ),
                ),
              const SizedBox(height: 10),
              _info(Icons.schedule, _eventDate(event.startAt.toDate())),
              if (event.location.isNotEmpty)
                _info(Icons.location_on_outlined, event.location),
              const SizedBox(height: 14),
              Row(
                children: [
                  UserAvatar(uid: event.hostId, radius: 17),
                  const SizedBox(width: 8),
                  const Text('จัดโดย '),
                  _EventHostName(uid: event.hostId),
                ],
              ),
              const Divider(height: 28),
              if (event.description.isNotEmpty)
                Text(event.description, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: current == 'going'
                            ? Colors.green
                            : null,
                      ),
                      onPressed:
                          event.isCancelled ||
                              !event.startAt.toDate().isAfter(DateTime.now())
                          ? null
                          : () => _respond(context, uid, current, 'going'),
                      icon: const Icon(Icons.check),
                      label: Text(
                        current == 'going' ? 'กำลังเข้าร่วม' : 'เข้าร่วม',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          event.isCancelled ||
                              !event.startAt.toDate().isAfter(DateTime.now())
                          ? null
                          : () => _respond(context, uid, current, 'interested'),
                      icon: Icon(
                        current == 'interested'
                            ? Icons.star
                            : Icons.star_outline,
                      ),
                      label: Text(
                        current == 'interested' ? 'สนใจแล้ว' : 'สนใจ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: service.responses(event.id),
                builder: (context, snap) {
                  final responses = snap.data?.docs ?? const [];
                  final going = responses
                      .where((doc) => doc.data()['status'] == 'going')
                      .length;
                  final interested = responses
                      .where((doc) => doc.data()['status'] == 'interested')
                      .length;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('$going เข้าร่วม'),
                          Text('$interested สนใจ'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );

  String _eventDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} เวลา ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _EventHostName extends StatelessWidget {
  final String uid;
  const _EventHostName({required this.uid});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) => Text(
          snap.data?.data()?['name'] as String? ?? 'สมาชิก',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
}
