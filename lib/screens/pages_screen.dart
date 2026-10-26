import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/page_service.dart';
import '../utils/image_data.dart';
import 'create_page_screen.dart';
import 'page_detail_screen.dart';

class PagesScreen extends StatefulWidget {
  const PagesScreen({super.key});
  @override
  State<PagesScreen> createState() => _PagesScreenState();
}

class _PagesScreenState extends State<PagesScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('เพจ'), actions: [
      IconButton(tooltip: 'สร้างเพจ', icon: const Icon(Icons.add), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePageScreen()))),
    ]),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'ค้นหาเพจจากชื่อหรือคำอธิบาย',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _query = ''); }),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            isDense: true,
          ),
        ),
      ),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PageService().pages(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('โหลดเพจไม่สำเร็จ: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.where((doc) {
            if (_query.isEmpty) return true;
            final data = doc.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final description = (data['description'] ?? '').toString().toLowerCase();
            return name.contains(_query) || description.contains(_query);
          }).toList();
          if (docs.isEmpty) return Center(child: Text(_query.isEmpty ? 'ยังไม่มีเพจ สร้างเพจแรกของคุณได้เลย' : 'ไม่พบเพจที่ตรงกับ “${_searchController.text.trim()}”'));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final isPrivate = data['privacy'] == 'private';
              final members = List<String>.from(data['memberIds'] ?? const []);
              final photo = data['photoUrl'] as String? ?? '';
              return Card(child: ListTile(
                leading: CircleAvatar(backgroundColor: isPrivate ? const Color(0xFFFFF3E0) : const Color(0xFFE3F2FD), backgroundImage: imageProviderFor(photo), child: photo.isNotEmpty ? null : Icon(isPrivate ? Icons.lock_outline : Icons.public, color: const Color(0xFF1877F2))),
                title: Text(data['name'] ?? 'เพจ', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((data['description'] ?? '').toString().isNotEmpty) Text(data['description'], maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${isPrivate ? 'ส่วนตัว' : 'สาธารณะ'} · สมาชิก ${members.length} คน', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PageDetailScreen(pageId: doc.id))),
              ));
            },
          );
        },
      )),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePageScreen())), icon: const Icon(Icons.add), label: const Text('สร้างเพจ')),
  );
}
