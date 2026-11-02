import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../widgets/user_avatar.dart';

/// เจ้าของกลุ่มเลือกเพื่อน (ติดตามกันทั้งสองฝ่าย) เพื่อเพิ่มเข้ากลุ่มที่มีอยู่แล้ว
class AddGroupMembersScreen extends StatefulWidget {
  final String groupId;
  final String ownerUid;
  final List<String> existingMembers;

  const AddGroupMembersScreen({
    required this.groupId,
    required this.ownerUid,
    required this.existingMembers,
    super.key,
  });

  @override
  State<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<AddGroupMembersScreen> {
  static const _maxMembers = 50;

  final _search = TextEditingController();
  final _selected = <String>{};
  List<DocumentSnapshot<Map<String, dynamic>>> _friends = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';

  // จำนวนที่ยังเพิ่มได้อีก (รวมแล้วไม่เกิน 50 คน)
  int get _slots => _maxMembers - widget.existingMembers.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _nameOf(DocumentSnapshot<Map<String, dynamic>> d) =>
      ((d.data()?['name'] ?? '') as String).trim();

  Future<void> _load() async {
    try {
      final list = await ChatService().mutualFriends(
        widget.ownerUid,
        exclude: widget.existingMembers.toSet(),
      );
      list.sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
      _friends = list;
    } catch (e) {
      _error = 'โหลดรายชื่อเพื่อนไม่สำเร็จ: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _toggle(String uid, bool selected) {
    if (selected && _selected.length >= _slots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('กลุ่มมีสมาชิกได้สูงสุด $_maxMembers คน')),
      );
      return;
    }
    setState(() => selected ? _selected.add(uid) : _selected.remove(uid));
  }

  Future<void> _add() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final count = await ChatService().addMembers(
        groupId: widget.groupId,
        ownerUid: widget.ownerUid,
        memberUids: _selected.toList(),
      );
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มสมาชิกแล้ว $count คน')),
      );
      if (navigator.mounted) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('เพิ่มสมาชิกไม่สำเร็จ: $e')),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _friends
        .where(
          (d) => _query.isEmpty || _nameOf(d).toLowerCase().contains(_query),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('เพิ่มเพื่อนเข้ากลุ่ม')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ค้นหาชื่อเพื่อน',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'เพื่อนที่ติดตามกันทั้งสองฝ่าย · เพิ่มได้อีก ${_slots < 0 ? 0 : _slots} คน',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : shown.isEmpty
                ? Center(
                    child: Text(
                      _friends.isEmpty
                          ? 'ไม่มีเพื่อนที่เพิ่มได้ (ทุกคนอยู่ในกลุ่มแล้ว หรือยังไม่ได้ติดตามกันทั้งสองฝ่าย)'
                          : 'ไม่พบชื่อที่ค้นหา',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final d = shown[i];
                      final name = _nameOf(d);
                      return CheckboxListTile(
                        key: ValueKey(d.id),
                        value: _selected.contains(d.id),
                        title: Text(name.isEmpty ? 'เพื่อน' : name),
                        secondary: UserAvatar(uid: d.id),
                        onChanged: (v) => _toggle(d.id, v == true),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty || _saving ? null : _add,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1),
                  label: Text('เพิ่มเข้ากลุ่ม (${_selected.length} คน)'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
