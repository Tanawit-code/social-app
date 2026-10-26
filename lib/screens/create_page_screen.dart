import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../services/storage_service.dart';

class CreatePageScreen extends StatefulWidget {
  const CreatePageScreen({super.key});
  @override
  State<CreatePageScreen> createState() => _CreatePageScreenState();
}

class _CreatePageScreenState extends State<CreatePageScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _photoBytes;
  String _privacy = 'public';
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _name.dispose(); _description.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 640, maxHeight: 640);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'เลือกรูปเพจไม่สำเร็จ: $e');
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _saving) {
      setState(() => _error = 'กรุณาระบุชื่อเพจ');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final uid = AuthService().currentUser?.uid;
      if (uid == null) throw Exception('กรุณาเข้าสู่ระบบอีกครั้ง');
      final photoUrl = _photoBytes == null ? null : await StorageService().uploadCoverImageBytes(bytes: _photoBytes!, uid: uid);
      await PageService().createPage(ownerId: uid, name: _name.text, description: _description.text, privacy: _privacy, photoUrl: photoUrl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สร้างเพจ')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Column(children: [
        CircleAvatar(radius: 46, backgroundImage: _photoBytes == null ? null : MemoryImage(_photoBytes!), child: _photoBytes == null ? const Icon(Icons.flag_outlined, size: 40) : null),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: _saving ? null : _pickPhoto, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('เพิ่มรูปเพจ')),
        if (_photoBytes != null) TextButton(onPressed: _saving ? null : () => setState(() => _photoBytes = null), child: const Text('ลบรูปที่เลือก')),
      ])),
      const SizedBox(height: 8),
      TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'ชื่อเพจ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag_outlined))),
      const SizedBox(height: 14),
      TextField(controller: _description, maxLength: 240, maxLines: 3, decoration: const InputDecoration(labelText: 'คำอธิบายเพจ', border: OutlineInputBorder(), alignLabelWithHint: true)),
      const SizedBox(height: 18),
      const Text('การมองเห็นเพจ', style: TextStyle(fontWeight: FontWeight.bold)),
      RadioListTile<String>(value: 'public', groupValue: _privacy, onChanged: _saving ? null : (value) => setState(() => _privacy = value!), title: const Text('สาธารณะ'), subtitle: const Text('ทุกคนดูโพสต์ได้ สมาชิกเท่านั้นที่โพสต์ได้')),
      RadioListTile<String>(value: 'private', groupValue: _privacy, onChanged: _saving ? null : (value) => setState(() => _privacy = value!), title: const Text('ส่วนตัว'), subtitle: const Text('ต้องส่งคำขอและได้รับอนุมัติก่อนจึงจะเห็นโพสต์')),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
      FilledButton.icon(onPressed: _saving ? null : _create, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add), label: const Text('สร้างเพจ')),
    ]),
  );
}
