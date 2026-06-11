import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class PttUser {
  const PttUser({required this.id, required this.name});
  final String id;
  final String name;
}

enum PttConnectionState { disconnected, connecting, connected }

class PttService extends ChangeNotifier {
  static const sampleRate = 16000;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  io.Socket? _socket;
  String? _socketId;

  PttConnectionState connectionState = PttConnectionState.disconnected;
  List<PttUser> users = [];
  String? currentSpeakerId;
  String? currentSpeakerName;
  String? statusHint;
  String? floorDeniedHolder;
  bool isTalking = false;
  bool hasMic = false;

  bool get isConnected => connectionState == PttConnectionState.connected;
  String? get socketId => _socketId;

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    hasMic = status.isGranted;
    notifyListeners();
    return hasMic;
  }

  Future<void> connect({
    required String serverUrl,
    required String room,
    required String name,
  }) async {
    await disconnect();

    if (!hasMic) {
      final ok = await requestMicPermission();
      if (!ok) {
        statusHint = 'Mic permission denied';
        notifyListeners();
        return;
      }
    }

    connectionState = PttConnectionState.connecting;
    statusHint = 'Kumokonekta...';
    notifyListeners();

    await FlutterPcmSound.setLogLevel(LogLevel.error);
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);

    final socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _socketId = socket.id;
      connectionState = PttConnectionState.connected;
      statusHint = 'Connected';
      socket.emitWithAck('join', {'room': room, 'name': name}, ack: (data) {
        final map = Map<String, dynamic>.from(data as Map);
        if (map['ok'] == true) {
          _setUsers(map['users']);
          statusHint = 'Pindutin at hawakan ang PTT button';
        } else {
          statusHint = map['error']?.toString() ?? 'Hindi makasali';
        }
        notifyListeners();
      });
      notifyListeners();
    });

    socket.onDisconnect((_) {
      connectionState = PttConnectionState.disconnected;
      statusHint = 'Disconnected';
      _stopRecording();
      isTalking = false;
      notifyListeners();
    });

    socket.on('users', (data) {
      _setUsers(data);
      notifyListeners();
    });

    socket.on('floor-granted', (_) {
      floorDeniedHolder = null;
      unawaited(_startRecording());
    });

    socket.on('floor-denied', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      floorDeniedHolder = map['holder']?.toString();
      statusHint = '$floorDeniedHolder ang nagsasalita — hintayin';
      isTalking = false;
      notifyListeners();
    });

    socket.on('ptt-start', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      currentSpeakerId = map['id']?.toString();
      currentSpeakerName = map['name']?.toString();
      notifyListeners();
    });

    socket.on('ptt-end', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      if (currentSpeakerId == map['id']?.toString()) {
        currentSpeakerId = null;
        currentSpeakerName = null;
      }
      if (!isTalking) {
        statusHint = 'Pindutin at hawakan ang PTT button';
      }
      notifyListeners();
    });

    socket.on('audio', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final chunk = map['chunk'];
      currentSpeakerName = map['name']?.toString();
      if (chunk is List<int>) {
        _playPcm(Uint8List.fromList(chunk));
      } else if (chunk is Uint8List) {
        _playPcm(chunk);
      }
      notifyListeners();
    });
  }

  void pttDown() {
    if (!isConnected || isTalking || !hasMic) return;
    isTalking = true;
    statusHint = 'Humihingi ng floor...';
    floorDeniedHolder = null;
    notifyListeners();
    _socket?.emit('ptt-down');
  }

  Future<void> pttUp() async {
    if (!isTalking) return;
    isTalking = false;
    await _stopRecording();
    _socket?.emit('ptt-up');
    statusHint = 'Pindutin at hawakan ang PTT button';
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _stopRecording();
    isTalking = false;
    _socket?.dispose();
    _socket = null;
    _socketId = null;
    users = [];
    currentSpeakerId = null;
    currentSpeakerName = null;
    connectionState = PttConnectionState.disconnected;
    notifyListeners();
  }

  void _setUsers(dynamic data) {
    if (data is! List) return;
    users = data
        .map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          return PttUser(
            id: map['id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
          );
        })
        .where((u) => u.id.isNotEmpty)
        .toList();
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;

    await _stopRecording();
    statusHint = '🔴 Nagsasalita ka...';
    notifyListeners();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
    );

    _micSub = stream.listen((chunk) {
      if (_socket?.connected == true && chunk.isNotEmpty) {
        _socket!.emit('audio', chunk);
      }
    });
  }

  Future<void> _stopRecording() async {
    await _micSub?.cancel();
    _micSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  void _playPcm(Uint8List bytes) {
    if (bytes.length < 2) return;
    final aligned = bytes.length - (bytes.length % 2);
    final samples = Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      aligned ~/ 2,
    );
    if (samples.isEmpty) return;
    unawaited(FlutterPcmSound.feed(PcmArrayInt16.fromList(samples.toList())));
  }

  @override
  void dispose() {
    unawaited(disconnect());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
