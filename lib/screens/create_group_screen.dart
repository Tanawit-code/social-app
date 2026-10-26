import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _selected = <String>{};
  final _uid = AuthService().currentUser?.uid ?? '';
  bool _saving = false;
  bool _loadingFriends = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _friends = [];
  String? _friendError;

  @override
  void initState() { super.initState(); _loadFriends(); }

  Future<void> _loadFriends() async {
    try {
      final db = FirebaseFirestore.instance;
      final owner = await db.collection('users').doc(_uid).get();
      final following = List<String>.from(owner.data()?['following'] ?? const []);
      final users = await db.collection('users').limit(200).get();
      _friends = users.docs.where((user) => user.id != _uid && following.contains(user.id) && List<String>.from(user.data()['following'] ?? const []).contains(_uid)).toList();
    } catch (e) { _friendError = 'โหลดรายชื่อเพื่อนไม่สำเร็จ: $e'; }
    finally { if (mounted) setState(() => _loadingFriends = false); }
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final id = await ChatService().createGroup(ownerUid: _uid, name: _name.text, memberUids: _selected.toList());
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: id)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สร้างกลุ่มไม่สำเร็จ: $e')));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สร้างกลุ่ม')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม', border: OutlineInputBorder()))),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Align(alignment: Alignment.centerLeft, child: Text('เลือกเพื่อน (ต้องติดตามกันทั้งสองฝ่าย)', style: TextStyle(fontWeight: FontWeight.bold)))),
      Expanded(child: _loadingFriends ? const Center(child: CircularProgressIndicator()) : _friendError != null ? Center(child: Text(_friendError!)) : _friends.isEmpty ? const Center(child: Text('ยังไม่มีเพื่อนที่ติดตามกันทั้งสองฝ่าย')) : ListView.builder(itemCount: _friends.length, itemBuilder: (context, i) {
        final friend = _friends[i]; final name = (friend.data()['name'] ?? '') as String;
        return CheckboxListTile(value: _selected.contains(friend.id), title: Text(name.isEmpty ? 'เพื่อน' : name), secondary: CircleAvatar(child: Text(name.isEmpty ? '?' : name.characters.first)), onChanged: (value) => setState(() => value == true ? _selected.add(friend.id) : _selected.remove(friend.id)));
      })),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _saving ? null : _create, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.group_add), label: Text('สร้างกลุ่ม (${_selected.length} คน)'))))),
    ]),
  );
}
