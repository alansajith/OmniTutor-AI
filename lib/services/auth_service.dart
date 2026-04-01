import 'package:firebase_auth/firebase_auth.dart';

/// Handles Firebase Authentication for OmniTutor AI.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Current user stream — emits whenever auth state changes.
  Stream<User?> get userStream => _auth.authStateChanges();

  /// Currently signed-in user (null if not signed in).
  User? get currentUser => _auth.currentUser;

  /// Sign in with email and password.
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Register a new account with email and password.
  Future<UserCredential> registerWithEmail(
      String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
