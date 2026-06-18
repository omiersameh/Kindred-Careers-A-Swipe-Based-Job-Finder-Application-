import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../models/job.dart';
import '../models/user_profile.dart';
import '../models/swipe_action.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

// ============================================================
// SERVICE: JobRecommendationService (v2.1 — Stateful Queue)
//
// Architecture:
//  • Persistent swipe exclusion via /api/swipes/record (SQLite backend).
//  • Server-side swiped IDs are merged with client exclude_ids before
//    any vector similarity search runs — users NEVER see a job twice.
//  • 5-Swipe / 60s Queue Pagination:
//      - Triggers a background feed fetch after every 5 swipes.
//      - OR after 60 seconds of active swiping (debounced).
//      - Appends new jobs strictly to the BOTTOM of the card deck.
//      - Zero UI interruption: active card is never disturbed.
//  • Rate limiting is handled server-side (ENABLE_RATE_LIMIT env var).
// ============================================================

/// Callback invoked when background queue update fetches new jobs.
/// The [newJobs] list should be APPENDED to the existing card deck bottom.
typedef OnQueueUpdate = void Function(List<Job> newJobs);

class JobRecommendationService {
  // ─── Base URL ────────────────────────────────────────────────
  static String get _baseUrl {
    final apiUrl = dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api/generate-cv';
    final uri = Uri.parse(apiUrl);
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  // ─── Buffer / Fetch config ───────────────────────────────────
  static const int _bufferMinSize = 15;   // Start background fetch when buffer drops below this
  static const int _fetchCount = 20;      // Jobs requested per feed call (from the 60-job pool)

  // ─── 5-Swipe / 60s Pagination Config ────────────────────────
  static const int _swipeTriggerThreshold = 5;    // Trigger after N swipes
  static const int _timeTriggerSeconds = 60;       // Trigger after N seconds of active swiping

  // ─── Internal state ──────────────────────────────────────────
  final List<Job> _buffer = [];
  final List<SwipeAction> _swipeHistory = [];
  final Set<String> _seenIds = {};         // All jobs shown (left + right), client-side

  bool _isFetching = false;
  bool _ingestTriggered = false;
  bool _feedExhausted = false;

  // Queue pagination counters
  int _swipesSinceLastFetch = 0;
  DateTime _lastFetchTime = DateTime.now();

  // Callback registered by HomeScreen for append-only updates
  OnQueueUpdate? _onQueueUpdate;

  // ─── Firebase UID ────────────────────────────────────────────
  String get _userId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid ?? 'anonymous';
  }

  // ─── Public API ──────────────────────────────────────────────

  /// Registers a callback that HomeScreen uses to append jobs to the deck bottom.
  /// Called once from HomeScreen.initState().
  void setOnQueueUpdate(OnQueueUpdate callback) {
    _onQueueUpdate = callback;
  }

  /// Initial load: fetches the first batch of unviewed jobs for this user.
  Future<List<Job>> getRecommendedJobsAsync(UserProfile profile) async {
    if (_feedExhausted && _buffer.isEmpty) return [];
    await _refetch(profile);
    return _getSorted();
  }

  List<Job> getRecommendedJobs(UserProfile profile) => _getSorted();

  bool get isFeedExhausted => _feedExhausted && _buffer.isEmpty;

  /// Records a swipe — marks job as seen, reports to backend (fire-and-forget),
  /// and checks the 5-swipe / 60s queue pagination triggers.
  void recordSwipe(SwipeAction action, UserProfile profile) {
    _swipeHistory.add(action);
    _seenIds.add(action.jobId);
    _buffer.removeWhere((j) => j.id == action.jobId);

    // Allow a refetch if buffer dropped below threshold
    if (_buffer.length < _bufferMinSize) _feedExhausted = false;

    // ── Report swipe to backend (fire-and-forget, no UI blocking) ──
    _reportSwipeToBackend(
      jobId: action.jobId,
      action: action.isLike ? 'like' : 'dislike',
    );

    // ── 5-Swipe / 60s Queue Pagination Logic ──────────────────────
    _swipesSinceLastFetch++;
    _checkQueueUpdateTriggers(profile);
  }

  void clearSwipeHistory() {
    _swipeHistory.clear();
    _buffer.clear();
    _seenIds.clear();
    _ingestTriggered = false;
    _feedExhausted = false;
    _swipesSinceLastFetch = 0;
    _lastFetchTime = DateTime.now();
  }

  /// Marks a job as seen even without a swipe (e.g. when a card is displayed).
  void markSeen(String jobId) => _seenIds.add(jobId);

  /// Manually trigger a personalized ingest using the user's profile.
  Future<void> triggerIngest(UserProfile profile) async {
    try {
      debugPrint('✨ Triggering personalized ingest for: ${profile.name}');
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/jobs/ingest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_profile': profile.toJson()}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ 60-Job bulk ingest started. Backend scraping with your profile.');
        _ingestTriggered = true;
      }
    } catch (e) {
      debugPrint('⚠️ Could not trigger ingest: $e');
    }
  }

  /// Called by HomeScreen's 60s periodic timer.
  /// Only fetches if the user has actually swiped since the last fetch (debounce).
  Future<void> triggerTimedQueueUpdate(UserProfile profile) async {
    if (_swipesSinceLastFetch == 0) {
      debugPrint('⏱️ [Queue] 60s timer fired but no active swipes — skipping fetch.');
      return;
    }
    debugPrint('⏱️ [Queue] 60s timer triggered queue update '
        '($_swipesSinceLastFetch swipes since last fetch)');
    await _performQueueUpdate(profile);
  }

  // ─── Internal — Queue Pagination Logic ───────────────────────

  /// Checks both triggers after each swipe. Runs silently in the background.
  void _checkQueueUpdateTriggers(UserProfile profile) {
    final secondsElapsed =
        DateTime.now().difference(_lastFetchTime).inSeconds;

    final swipeTrigger = _swipesSinceLastFetch >= _swipeTriggerThreshold;
    final timeTrigger = secondsElapsed >= _timeTriggerSeconds &&
        _swipesSinceLastFetch > 0;

    if (swipeTrigger) {
      debugPrint('🃏 [Queue] 5-swipe trigger fired (swipes: $_swipesSinceLastFetch)');
      _performQueueUpdate(profile);
    } else if (timeTrigger) {
      debugPrint('⏱️ [Queue] 60s+active swipe trigger fired (swipes: $_swipesSinceLastFetch)');
      _performQueueUpdate(profile);
    }
  }

  /// Fetches a fresh batch of unviewed jobs and appends them to the buffer bottom.
  /// Zero UI interruption: uses [_onQueueUpdate] callback to notify HomeScreen.
  Future<void> _performQueueUpdate(UserProfile profile) async {
    if (_isFetching) {
      debugPrint('🔄 [Queue] Already fetching — skipping duplicate trigger.');
      return;
    }

    // Reset counters immediately to prevent double-triggering
    _swipesSinceLastFetch = 0;
    _lastFetchTime = DateTime.now();

    debugPrint('📡 [Queue] Background update: fetching next batch...');
    await _refetch(profile);

    final newBatch = _getSorted();
    if (newBatch.isNotEmpty && _onQueueUpdate != null) {
      // Notify HomeScreen to APPEND to the bottom — current card is untouched
      _onQueueUpdate!(newBatch);
      debugPrint('✅ [Queue] Appended ${newBatch.length} jobs to deck bottom.');
    }
  }

  // ─── Internal — Feed Fetch ───────────────────────────────────

  List<Job> _getSorted() {
    final swipedIds = _swipeHistory.map((s) => s.jobId).toSet();
    // Backend already sorts by combined score (65% match + 35% recency)
    return _buffer.where((j) => !swipedIds.contains(j.id)).toList();
  }

  /// Fetches jobs from /api/jobs/feed with:
  ///   - user_id → backend merges server-side swiped IDs before vector search
  ///   - exclude_ids → additional client-side session exclusions
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
              'user_id': _userId,           // ← Server merges swiped IDs in SQLite
              'n': _fetchCount,
              'exclude_ids': _seenIds.toList(), // Client-side seen IDs (belt + suspenders)
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
        debugPrint('✅ [Feed] Fetched $added new jobs. Buffer: ${_buffer.length}');

        if (newJobs.isEmpty) {
          _feedExhausted = true;
          debugPrint('📭 [Feed] No more unviewed jobs — feed exhausted.');
        }
      } else if (response.statusCode == 429) {
        // Rate limit hit (only when ENABLE_RATE_LIMIT=true on server)
        final body = jsonDecode(response.body);
        final retryAfter = body['retry_after_seconds'] ?? 0;
        debugPrint('🚫 [Feed] Rate limit exceeded. Retry after ${retryAfter}s. '
            '(Toggle ENABLE_RATE_LIMIT=False in backend/.env to disable)');
        _feedExhausted = true;
      } else if (response.statusCode == 503) {
        final body = jsonDecode(response.body);
        final detail = (body['detail'] ?? '').toString();

        if (detail.contains('empty')) {
          if (!_ingestTriggered) {
            debugPrint('⚠️ DB empty. Auto-triggering 60-job bulk scrape...');
            await triggerIngest(profile);
          }
        } else {
          _feedExhausted = true;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Backend unreachable or timed out: $e');
      debugPrint('🔄 Falling back to offline mock jobs.');

      final mockJobs = [
        Job(
          id: 'job_${DateTime.now().millisecondsSinceEpoch}_1',
          title: 'Senior Flutter Developer',
          company: 'TechCorp',
          location: 'Remote',
          jobType: 'Full-time',
          description: 'Looking for an experienced Flutter engineer...',
          requiredSkills: ['Flutter', 'Dart', 'Firebase'],
          industry: 'Technology',
          matchScore: 0.95,
          vibeTag: '🚀 High Growth',
          summaryBullets: ['Lead mobile app team', 'Migrate legacy apps to Flutter'],
        ),
        Job(
          id: 'job_${DateTime.now().millisecondsSinceEpoch}_2',
          title: 'Digital Marketing Manager',
          company: 'Growth.io',
          location: 'Hybrid',
          jobType: 'Full-time',
          description: 'Drive growth and user acquisition...',
          requiredSkills: ['SEO', 'Content Strategy', 'Google Analytics'],
          industry: 'Marketing',
          matchScore: 0.88,
          vibeTag: '📈 Impact',
          summaryBullets: ['Manage \$1M ad spend', 'Run A/B tests'],
        ),
      ];

      final existingIds = _buffer.map((j) => j.id).toSet();
      int added = 0;
      for (final job in mockJobs) {
        if (!existingIds.contains(job.id) && !_seenIds.contains(job.id)) {
          _buffer.add(job);
          added++;
        }
      }

      if (added == 0) _feedExhausted = true;
    } finally {
      _isFetching = false;
    }
  }

  // ─── Internal — Backend Swipe Reporting ──────────────────────

  /// Posts a swipe event to /api/swipes/record.
  /// Fire-and-forget: errors are silently logged, never thrown to UI.
  Future<void> _reportSwipeToBackend({
    required String jobId,
    required String action,
  }) async {
    try {
      final uid = _userId;
      if (uid == 'anonymous') return; // Don't track anonymous users

      await http
          .post(
            Uri.parse('$_baseUrl/api/swipes/record'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': uid,
              'job_id': jobId,
              'action': action,
            }),
          )
          .timeout(const Duration(seconds: 5));

      debugPrint('📝 [Swipe] Recorded: $action on $jobId for user $uid');
    } catch (e) {
      // Non-blocking: swipe reporting failure must never affect the UI
      debugPrint('⚠️ [Swipe] Could not report swipe to backend: $e');
    }
  }
}
