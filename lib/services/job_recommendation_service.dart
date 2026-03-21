import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/job.dart';
import '../models/user_profile.dart';
import '../models/swipe_action.dart';

// ============================================================
// SERVICE: JobRecommendationService (Phase 3 — RAG Backend)
//
// • Tracks ALL seen job IDs (left + right) per app session
// • Sends them as exclude_ids on every feed request so the
//   same listing never appears twice in the same session.
// • When no new jobs remain → signals empty feed cleanly.
// • Jobs returned sorted by backend: 65% match + 35% recency.
// ============================================================

class JobRecommendationService {
  static const String _baseUrl = 'http://192.168.100.12:8000'; // PC's actual IP
  static const int _bufferMinSize = 30;
  static const int _fetchCount = 40;

  final List<Job> _buffer = [];
  final List<SwipeAction> _swipeHistory = [];
  final Set<String> _seenIds = {}; // All jobs shown to user (left + right)

  bool _isFetching = false;
  bool _ingestTriggered = false;
  bool _feedExhausted = false; // True when backend says "no more new jobs"

  // ─── Public API ────────────────────────────────────────────

  /// Returns jobs from the buffer. An empty list means feed is exhausted.
  Future<List<Job>> getRecommendedJobsAsync(UserProfile profile) async {
    if (_feedExhausted && _buffer.isEmpty) return [];
    await _refetch(profile);
    return _getSorted();
  }

  List<Job> getRecommendedJobs(UserProfile profile) => _getSorted();

  /// Whether the user has swiped through all currently available listings.
  bool get isFeedExhausted => _feedExhausted && _buffer.isEmpty;

  /// Records a swipe — marks job as seen so it is excluded from future requests.
  void recordSwipe(SwipeAction action) {
    _swipeHistory.add(action);
    _seenIds.add(action.jobId);
    _buffer.removeWhere((j) => j.id == action.jobId);
    // If buffer dropped below threshold, allow a refetch
    if (_buffer.length < _bufferMinSize) _feedExhausted = false;
  }

  void clearSwipeHistory() {
    _swipeHistory.clear();
    _buffer.clear();
    _seenIds.clear();
    _ingestTriggered = false;
    _feedExhausted = false;
  }

  // Also track when a job card is displayed (even without swipe)
  void markSeen(String jobId) => _seenIds.add(jobId);

  /// Manually trigger a personalized ingest using the user's profile.
  Future<void> triggerIngest(UserProfile profile) async {
    try {
      print('✨ Triggering personalized ingest for: ${profile.name}');
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/jobs/ingest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_profile': profile.toJson()}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Personalized ingest started. Backend scraping with your profile.');
        _ingestTriggered = true;
      }
    } catch (e) {
      print('⚠️ Could not trigger ingest: $e');
    }
  }

  // ─── Internal ──────────────────────────────────────────────

  List<Job> _getSorted() {
    final swipedIds = _swipeHistory.map((s) => s.jobId).toSet();
    // Backend already sorts by combined score — preserve that order
    return _buffer.where((j) => !swipedIds.contains(j.id)).toList();
  }

  /// Fetches jobs from /api/jobs/feed with exclude_ids to prevent duplicates.
  Future<void> _refetch(UserProfile profile) async {
    if (_isFetching || _feedExhausted) return;
    if (_buffer.length >= _bufferMinSize) return;

    _isFetching = true;
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/jobs/feed'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_profile': profile.toJson(),
              'n': _fetchCount,
              'exclude_ids': _seenIds.toList(), // Never show already-seen jobs
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final newJobs = data.map((j) => Job.fromJson(j)).toList();
        final existingIds = _buffer.map((j) => j.id).toSet();
        int added = 0;
        for (final job in newJobs) {
          if (!existingIds.contains(job.id) && !_seenIds.contains(job.id)) {
            _buffer.add(job);
            added++;
          }
        }
        print('✅ Fetched $added new jobs. Buffer: ${_buffer.length}');
      } else if (response.statusCode == 503) {
        final body = jsonDecode(response.body);
        final detail = (body['detail'] ?? '').toString();

        if (detail.contains('empty')) {
          if (!_ingestTriggered) {
             print('⚠️ DB empty. Auto-triggering personalized scrape...');
             await triggerIngest(profile);
          }
        } else {
          _feedExhausted = true;
        }
      }
    } catch (e) {
      print('⚠️ Backend unreachable: $e');
    } finally {
      _isFetching = false;
    }
  }
}
