import 'package:flutter/material.dart';

import '../services/ptt_service.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.ptt,
    required this.name,
    required this.room,
    required this.serverUrl,
  });

  final PttService ptt;
  final String name;
  final String room;
  final String serverUrl;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  @override
  void initState() {
    super.initState();
    widget.ptt.addListener(_onUpdate);
    widget.ptt.connect(serverUrl: widget.serverUrl, room: widget.room, name: widget.name);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    widget.ptt.removeListener(_onUpdate);
    widget.ptt.disconnect();
    super.dispose();
  }

  Future<void> _leave() async {
    await widget.ptt.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ptt = widget.ptt;
    final connected = ptt.isConnected;
    final speaker = ptt.currentSpeakerName;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? const Color(0xFF3DD68C) : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(connected ? 'Connected' : 'Connecting...'),
                ],
              ),
              const SizedBox(height: 20),
              Text('CHANNEL', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text(
                widget.room,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF243044),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text('STATUS', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    Text(
                      speaker != null ? '$speaker nagsasalita...' : 'Nakikinig...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: speaker != null ? const Color(0xFFF5C542) : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Listener(
                onPointerDown: (_) {
                  if (connected && ptt.hasMic) ptt.pttDown();
                },
                onPointerUp: (_) => ptt.pttUp(),
                onPointerCancel: (_) => ptt.pttUp(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: ptt.isTalking
                          ? [const Color(0xFFFF9090), const Color(0xFFFF1A1A)]
                          : [const Color(0xFFFF7070), const Color(0xFFFF4D4D)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ptt.isTalking
                            ? const Color(0x99FF1A1A)
                            : const Color(0x73FF4D4D),
                        blurRadius: ptt.isTalking ? 32 : 20,
                        spreadRadius: ptt.isTalking ? 4 : 0,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'HOLD\nTO TALK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                ptt.statusHint ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ONLINE',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: ListView.builder(
                  itemCount: ptt.users.length,
                  itemBuilder: (context, i) {
                    final user = ptt.users[i];
                    final isSelf = user.id == ptt.socketId;
                    final talking = user.id == ptt.currentSpeakerId;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        talking ? Icons.volume_up : Icons.circle,
                        size: talking ? 20 : 10,
                        color: const Color(0xFF3DD68C),
                      ),
                      title: Text(
                        isSelf ? '${user.name} (ikaw)' : user.name,
                        style: TextStyle(
                          color: isSelf ? const Color(0xFF3DD68C) : null,
                          fontWeight: talking ? FontWeight.bold : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
              OutlinedButton(
                onPressed: _leave,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  side: const BorderSide(color: Color(0xFF243044)),
                ),
                child: const Text('Umalis sa channel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
