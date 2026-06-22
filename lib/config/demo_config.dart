// ============================================================
// CONFIG: DemoConfig
// Compile-time flag for Demo Mode.
//
// Build commands:
//   Live:  flutter run
//   Demo:  flutter run --dart-define=DEMO_MODE=true
// ============================================================

class DemoConfig {
  /// Compile-time constant — true when built with --dart-define=DEMO_MODE=true
  static const bool isDemoMode =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  /// The currently selected demo member (1, 2, or 3).
  /// Set at sign-in time by the mock login screen.
  static int currentMember = 1;

  /// Member display names for the login tabs.
  static const List<Map<String, String>> members = [
    {
      'label': 'Member 1 (AI)',
      'emoji': '🧠',
      'email': 'ahmed.mansour@demo.kc',
      'password': 'demo123',
    },
    {
      'label': 'Member 2 (Growth)',
      'emoji': '📈',
      'email': 'salma.elsherif@demo.kc',
      'password': 'demo123',
    },
    {
      'label': 'Member 3 (Creative)',
      'emoji': '🎬',
      'email': 'omar.tarek@demo.kc',
      'password': 'demo123',
    },
  ];

  /// Returns the asset path prefix for the current member's data.
  static String get memberDataPrefix => 'assets/mock_data/member${currentMember}';

  /// Returns the mock CV PDF asset path for a given job index.
  static String mockCvPath(int jobIndex) =>
      'assets/mock_cvs/m${currentMember}_job$jobIndex.pdf';
}
