import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _privacy = 'public';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final uid = AuthService().currentUser?.uid ?? '';
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'กรุณาตั้งชื่อชุมชน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await CommunityService().create(
        ownerId: uid,
        name: _name.text,
        description: _description.text,
        privacy: _privacy,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = 'สร้างชุมชนไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สร้างชุมชน')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'ชื่อชุมชน',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLength: 500,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'คำอธิบาย',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _privacy,
          decoration: const InputDecoration(labelText: 'การเข้าถึง'),
          items: const [
            DropdownMenuItem(
              value: 'public',
              child: Text('สาธารณะ — ทุกคนดูโพสต์และเข้าร่วมได้'),
            ),
            DropdownMenuItem(
              value: 'private',
              child: Text('ส่วนตัว — ต้องได้รับอนุมัติก่อน'),
            ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value != null) setState(() => _privacy = value);
                },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.groups_2_outlined),
          label: const Text('สร้างชุมชน'),
        ),
      ],
    ),
  );
}
