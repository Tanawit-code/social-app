import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/follow_service.dart';
import '../widgets/user_avatar.dart';
import '../screens/profile_screen.dart';

class SuggestedPeople extends StatelessWidget {
  final String uid;
  const SuggestedPeople({required this.uid, super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, meSnap) {
      if (!meSnap.hasData) return const SizedBox.shrink();
      final following = List<String>.from(meSnap.data!.data()?['following'] ?? const []);
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').where('isPrivate', isEqualTo: false).limit(200).snapshots(),
        builder: (context, usersSnap) {
          if (!usersSnap.hasData) return const SizedBox.shrink();
          final suggestions = usersSnap.data!.docs.where((doc) => doc.id != uid && !following.contains(doc.id)).toList();
          suggestions.sort((a, b) {
            final aFollowsMe = List<String>.from(a.data()['followers'] ?? const []).contains(uid);
            final bFollowsMe = List<String>.from(b.data()['followers'] ?? const []).contains(uid);
            return (bFollowsMe ? 1 : 0).compareTo(aFollowsMe ? 1 : 0);
          });
          if (suggestions.isEmpty) return const SizedBox.shrink();
          final visible = suggestions.take(12).toList();
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(right: 12), child: Text('แนะนำให้ติดตาม', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                const SizedBox(height: 10),
                SizedBox(
                  height: 176,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => _SuggestedPersonCard(uid: uid, person: visible[index]),
                  ),
                ),
              ]),
            ),
          );
        },
      );
    },
  );
}

class _SuggestedPersonCard extends StatefulWidget {
  final String uid;
  final QueryDocumentSnapshot<Map<String, dynamic>> person;
  const _SuggestedPersonCard({required this.uid, required this.person});
  @override
  State<_SuggestedPersonCard> createState() => _SuggestedPersonCardState();
}

class _SuggestedPersonCardState extends State<_SuggestedPersonCard> {
  bool _loading = false;

  Future<void> _follow() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await FollowService().follow(me: widget.uid, target: widget.person.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ติดตามไม่สำเร็จ: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.person.data()['name'] ?? '') as String;
    final followsMe = List<String>.from(widget.person.data()['followers'] ?? const []).contains(widget.uid);
    return SizedBox(
      width: 132,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(children: [
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: widget.person.id))), child: UserAvatar(uid: widget.person.id, radius: 28)),
            const SizedBox(height: 7),
            GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: widget.person.id))), child: Text(name.isEmpty ? 'ผู้ใช้' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            const SizedBox(height: 2),
            Text(followsMe ? 'ติดตามคุณแล้ว' : 'แนะนำสำหรับคุณ', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54)),
            const Spacer(),
            SizedBox(width: double.infinity, height: 30, child: FilledButton.tonal(onPressed: _loading ? null : _follow, style: FilledButton.styleFrom(padding: EdgeInsets.zero), child: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ติดตาม', style: TextStyle(fontSize: 12)))),
          ]),
        ),
      ),
    );
  }
}
