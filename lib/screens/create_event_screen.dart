import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  DateTime? _startAt;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _chooseDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _startAt ?? DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _startAt ?? DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _startAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _error = null;
    });
  }

  Future<void> _create() async {
    final uid = AuthService().currentUser?.uid ?? '';
    if (_name.text.trim().isEmpty || _startAt == null) {
      setState(() => _error = 'กรุณาใส่ชื่อและวันเวลาของกิจกรรม');
      return;
    }
    if (!_startAt!.isAfter(DateTime.now())) {
      setState(() => _error = 'วันเวลาต้องอยู่ในอนาคต');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await EventService().create(
        hostId: uid,
        name: _name.text,
        description: _description.text,
        location: _location.text,
        startAt: _startAt!,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = 'สร้างกิจกรรมไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สร้างกิจกรรม')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'ชื่อกิจกรรม',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLength: 2000,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'รายละเอียด',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _location,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'สถานที่ (ไม่บังคับ)',
            prefixIcon: Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _chooseDateTime,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(
            _startAt == null
                ? 'เลือกวันและเวลา'
                : '${_startAt!.day}/${_startAt!.month}/${_startAt!.year} · ${_startAt!.hour.toString().padLeft(2, '0')}:${_startAt!.minute.toString().padLeft(2, '0')}',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_available_outlined),
          label: const Text('เผยแพร่กิจกรรม'),
        ),
      ],
    ),
  );
}
