import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../config/demo_config.dart';
import '../../models/job.dart';

// ============================================================
// SERVICE: MockJobService
// Reads job cards from local JSON assets for Demo Mode.
// Replaces JobRecommendationService — zero HTTP, zero backend.
// ============================================================

class MockJobService {
  static List<Job>? _cachedJobs;

  /// Loads the 20 jobs for the current demo member from assets.
  Future<List<Job>> getJobs() async {
    if (_cachedJobs != null) return List.from(_cachedJobs!);

    try {
      final path = '${DemoConfig.memberDataPrefix}_jobs.json';
      final jsonStr = await rootBundle.loadString(path);
      final List<dynamic> data = jsonDecode(jsonStr);
      _cachedJobs = data.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
      debugPrint('📋 [MockJobService] Loaded ${_cachedJobs!.length} jobs for member ${DemoConfig.currentMember}');
      return List.from(_cachedJobs!);
    } catch (e) {
      debugPrint('❌ [MockJobService] Failed to load jobs: $e');
      return [];
    }
  }

  /// Returns the index of a job in the original loaded list.
  /// Used to determine which mock PDF to load.
  int getJobIndex(String jobId) {
    if (_cachedJobs == null) return 0;
    final idx = _cachedJobs!.indexWhere((j) => j.id == jobId);
    return idx >= 0 ? idx : 0;
  }

  /// Clears the cache (e.g., on sign-out / member switch).
  void clearCache() {
    _cachedJobs = null;
  }
}
