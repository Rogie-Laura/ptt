class AppConfig {
  /// Set at build time: --dart-define=PTT_SERVER=https://your-server.onrender.com
  static const serverUrl = String.fromEnvironment(
    'PTT_SERVER',
    defaultValue: 'https://ptt-server.onrender.com',
  );
}
