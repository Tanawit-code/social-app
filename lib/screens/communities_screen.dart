import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../models/event_model.dart';
import '../services/community_service.dart';
import '../services/event_service.dart';
import 'community_detail_screen.dart';
import 'create_community_screen.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            hintText: 'ค้นหาชุมชนหรือกิจกรรม',
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'สร้างชุมชน',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateCommunityScreen()),
            ),
            icon: const Icon(Icons.groups_2_outlined),
          ),
          IconButton(
            tooltip: 'สร้างกิจกรรม',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateEventScreen()),
            ),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.groups_outlined), text: 'ชุมชน'),
            Tab(icon: Icon(Icons.event_outlined), text: 'กิจกรรม'),
          ],
        ),
      ),
      body: TabBarView(children: [_communityList(), _eventList()]),
    ),
  );

  Widget _communityList() => StreamBuilder<List<Community>>(
    stream: CommunityService().streamCommunities(),
    builder: (context, snap) {
      if (snap.hasError)
        return Center(child: Text('โหลดชุมชนไม่สำเร็จ: ${snap.error}'));
      if (!snap.hasData)
        return const Center(child: CircularProgressIndicator());
      final items = snap.data!
          .where(
            (community) =>
                _query.isEmpty ||
                '${community.name} ${community.description}'
                    .toLowerCase()
                    .contains(_query),
          )
          .toList();
      if (items.isEmpty)
        return Center(
          child: Text(
            _query.isEmpty
                ? 'ยังไม่มีชุมชน สร้างชุมชนแรกได้เลย'
                : 'ไม่พบชุมชนที่ตรงกับ “${_search.text}”',
          ),
        );
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final community = items[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  community.privacy == 'private'
                      ? Icons.lock_outline
                      : Icons.groups_2_outlined,
                ),
              ),
              title: Text(
                community.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${community.privacy == 'private' ? 'ส่วนตัว' : 'สาธารณะ'} · ${community.description}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityDetailScreen(community: community),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _eventList() => StreamBuilder<List<SocialEvent>>(
    stream: EventService().stream(),
    builder: (context, snap) {
      if (snap.hasError)
        return Center(child: Text('โหลดกิจกรรมไม่สำเร็จ: ${snap.error}'));
      if (!snap.hasData)
        return const Center(child: CircularProgressIndicator());
      final now = DateTime.now();
      final items = snap.data!
          .where(
            (event) =>
                !event.isCancelled &&
                event.startAt.toDate().isAfter(now) &&
                (_query.isEmpty ||
                    '${event.name} ${event.description} ${event.location}'
                        .toLowerCase()
                        .contains(_query)),
          )
          .toList();
      if (items.isEmpty)
        return Center(
          child: Text(
            _query.isEmpty
                ? 'ยังไม่มีกิจกรรมที่กำลังจะมาถึง'
                : 'ไม่พบกิจกรรมที่ตรงกับ “${_search.text}”',
          ),
        );
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final event = items[index];
          final date = event.startAt.toDate();
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.event_available_outlined),
              ),
              title: Text(
                event.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${event.location.isEmpty ? '' : ' · ${event.location}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(event: event),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
