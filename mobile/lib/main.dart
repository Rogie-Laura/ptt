import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/join_screen.dart';
import 'services/ptt_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarBrightness: Brightness.dark),
  );
  runApp(const PttApp());
}

class PttApp extends StatefulWidget {
  const PttApp({super.key});

  @override
  State<PttApp> createState() => _PttAppState();
}

class _PttAppState extends State<PttApp> {
  final _ptt = PttService();

  @override
  void dispose() {
    _ptt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PTT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1419),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF4D4D),
          surface: Color(0xFF1A2332),
        ),
        useMaterial3: true,
      ),
      home: JoinScreen(ptt: _ptt),
    );
  }
}
