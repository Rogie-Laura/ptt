import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/ptt_service.dart';
import 'room_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.ptt});

  final PttService ptt;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _nameCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _serverCtrl = TextEditingController(text: AppConfig.serverUrl);
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text = prefs.getString('ptt-name') ?? '';
      _roomCtrl.text = prefs.getString('ptt-room') ?? '';
      _serverCtrl.text = prefs.getString('ptt-server') ?? _serverCtrl.text;
    });
  }

  Future<void> _join() async {
    final name = _nameCtrl.text.trim();
    final room = _roomCtrl.text.trim();
    final server = _serverCtrl.text.trim();

    if (name.isEmpty || room.isEmpty || server.isEmpty) {
      setState(() => _error = 'Punan ang lahat ng fields.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ptt-name', name);
    await prefs.setString('ptt-room', room);
    await prefs.setString('ptt-server', server);

    final micOk = await widget.ptt.requestMicPermission();
    if (!micOk) {
      setState(() {
        _loading = false;
        _error = 'Kailangan ng microphone permission.';
      });
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          ptt: widget.ptt,
          name: name,
          room: room,
          serverUrl: server,
        ),
      ),
    );

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            const Text(
              '📻 PTT',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Push-to-talk walkie style',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 32),
            _field('Pangalan mo', _nameCtrl, 'hal. Juan'),
            const SizedBox(height: 16),
            _field('Room / Channel', _roomCtrl, 'hal. team-alpha'),
            const SizedBox(height: 16),
            _field('Server URL', _serverCtrl, 'http://192.168.x.x:3001'),
            const SizedBox(height: 8),
            Text(
              'Default: online server (Render).\n'
              'Local test: http://10.0.2.2:3001 o IP ng PC',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _join,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D4D),
                minimumSize: const Size.fromHeight(48),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sumali sa channel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFF1A2332),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF243044)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF243044)),
            ),
          ),
        ),
      ],
    );
  }
}
