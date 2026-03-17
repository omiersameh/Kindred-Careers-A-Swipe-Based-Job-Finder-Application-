import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// ============================================================
// SERVICE: AuthService
// Wraps Firebase Authentication for email/password + Google.
// ============================================================

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _google = GoogleSignIn();

  /// Current signed-in user (null if not authenticated).
  static User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes — use with StreamBuilder in main.dart.
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Email / Password ──────────────────────────────────────

  /// Signs in with email and password.
  /// Returns null on success; returns error message string on failure.
  static Future<String?> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  /// Creates a new account with email and password.
  /// Returns null on success; returns error message string on failure.
  static Future<String?> signUpWithEmail(
      String email, String password, String displayName) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      await cred.user?.updateDisplayName(displayName.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  // ─── Google Sign-In ────────────────────────────────────────

  /// Initiates the Google OAuth flow.
  /// Returns null on success; returns error message on failure.
  static Future<String?> signInWithGoogle() async {
    try {
      final googleUser = await _google.signIn();
      if (googleUser == null) return 'Sign-in cancelled.';
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    } catch (_) {
      return 'Google sign-in failed. Please try again.';
    }
  }

  // ─── Sign Out ──────────────────────────────────────────────

  static Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }

  // ─── Password Reset ────────────────────────────────────────

  static Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _friendlyError(e.code);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────

  static String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
