import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles all Firestore read/write operations for OmniTutor AI.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Saves a tutoring session summary to the `sessions` collection.
  ///
  /// [uid]       – Firebase Auth UID of the current user
  /// [subject]   – Subject / topic detected or typed (e.g. "Calculus")
  /// [aiResponse]– The AI tutor's response text for this interaction
  Future<void> saveSession({
    required String uid,
    required String subject,
    required String aiResponse,
  }) async {
    await _db.collection('sessions').add({
      'uid': uid,
      'subject': subject,
      'aiResponse': aiResponse,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Returns a stream of all sessions belonging to [uid],
  /// ordered by most-recent first. Useful for a history view.
  Stream<QuerySnapshot<Map<String, dynamic>>> sessionsStream(String uid) {
    return _db
        .collection('sessions')
        .where('uid', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ── Gamification ───────────────────────────────────────────────────────

  /// Returns a stream of the user's global stats (XP, Streaks, etc.)
  Stream<DocumentSnapshot<Map<String, dynamic>>> userStatsStream(String uid) {
    return _db.collection('user_stats').doc(uid).snapshots();
  }

  /// Awards Brain Points (XP) and calculates daily streaks.
  ///
  /// Logic:
  /// - Yesterday: Streak + 1
  /// - Today: Same Streak
  /// - > 1 day: Streak = 1
  Future<void> awardPoints(String uid, int points) async {
    final docRef = _db.collection('user_stats').doc(uid);
    final doc = await docRef.get();
    final now = DateTime.now();

    if (!doc.exists) {
      // First time user
      await docRef.set({
        'totalXP': points,
        'currentStreak': 1,
        'lastActiveDate': Timestamp.fromDate(now),
        'uid': uid,
      });
      return;
    }

    final data = doc.data()!;
    final int currentXP = data['totalXP'] ?? 0;
    final int currentStreak = data['currentStreak'] ?? 0;
    final Timestamp lastTimestamp = data['lastActiveDate'] as Timestamp;
    final lastDate = lastTimestamp.toDate();

    // Logic to calculate streak
    int newStreak = currentStreak;
    final diffInDays = _daysBetween(lastDate, now);

    if (diffInDays == 1) {
      // It was yesterday!
      newStreak += 1;
    } else if (diffInDays > 1) {
      // Breaking the streak
      newStreak = 1;
    }
    // If diffInDays == 0 (same day), streak stays the same

    await docRef.update({
      'totalXP': currentXP + points,
      'currentStreak': newStreak,
      'lastActiveDate': Timestamp.fromDate(now),
    });
  }

  /// Helper to calculate full days between two dates regardless of time.
  int _daysBetween(DateTime from, DateTime to) {
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);
    return to.difference(from).inDays;
  }
}
