// ============================================================
// SERVICE: MockAuthService
// Provides a fake authentication layer for Demo Mode.
// Completely bypasses Firebase — zero network dependency.
// ============================================================

import '../../config/demo_config.dart';

/// Lightweight fake user object mimicking the properties
/// that the rest of the app expects from FirebaseAuth.User.
class MockUser {
  final String uid;
  final String email;
  final String displayName;

  const MockUser({
    required this.uid,
    required this.email,
    required this.displayName,
  });
}

class MockAuthService {
  static MockUser? _currentUser;

  /// The currently "signed-in" mock user.
  static MockUser? get currentUser => _currentUser;

  /// Whether a mock user is currently signed in.
  static bool get isSignedIn => _currentUser != null;

  /// Signs in as the given demo member (1, 2, or 3).
  /// Sets [DemoConfig.currentMember] and creates a [MockUser].
  static void signInAsMember(int memberIndex) {
    DemoConfig.currentMember = memberIndex;
    final memberData = DemoConfig.members[memberIndex - 1];

    final names = {
      1: 'Ahmed Mansour',
      2: 'Salma El-Sherif',
      3: 'Omar Tarek',
    };

    _currentUser = MockUser(
      uid: 'demo_member_$memberIndex',
      email: memberData['email']!,
      displayName: names[memberIndex]!,
    );
  }

  /// Signs out the current mock user.
  static void signOut() {
    _currentUser = null;
  }
}
