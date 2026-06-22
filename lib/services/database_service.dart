import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/demo_config.dart';
import '../models/job.dart';
import '../models/cv.dart';

class DatabaseService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _userId => DemoConfig.isDemoMode ? null : _auth.currentUser?.uid;

  /// Fetch all matched jobs and their CVs for the current user.
  Future<Map<String, dynamic>> loadUserMatches() async {
    if (DemoConfig.isDemoMode) {
      // Demo mode starts with zero matches in memory
      return {'jobs': <Job>[], 'cvs': <String, CV>{}};
    }

    final uid = _userId;
    if (uid == null) return {'jobs': <Job>[], 'cvs': <String, CV>{}};

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('matches')
          .get();

      final List<Job> jobs = [];
      final Map<String, CV> cvs = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['job'] != null) {
          final job = Job.fromJson(data['job']);
          jobs.add(job);
        }
        if (data['cv'] != null) {
          final cv = CV.fromJson(data['cv']);
          cvs[cv.jobId] = cv;
        }
      }

      return {'jobs': jobs, 'cvs': cvs};
    } catch (e) {
      print('Error loading user matches: $e');
      return {'jobs': <Job>[], 'cvs': <String, CV>{}};
    }
  }

  /// Save or update a job match and its associated CV.
  Future<void> saveMatch(Job job, [CV? cv]) async {
    if (DemoConfig.isDemoMode) return; // Matches are kept only in memory during demo

    final uid = _userId;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('matches')
          .doc(job.id)
          .set({
        'job': job.toJson(),
        if (cv != null) 'cv': cv.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving match: $e');
    }
  }

  /// Remove a job match.
  Future<void> deleteMatch(String jobId) async {
    if (DemoConfig.isDemoMode) return;

    final uid = _userId;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('matches')
          .doc(jobId)
          .delete();
    } catch (e) {
      print('Error deleting match: $e');
    }
  }
}
