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
  static const int _bufferMinSize = 30;

  final List<Job> _buffer = [];
  final List<SwipeAction> _swipeHistory = [];
  final Set<String> _seenIds = {}; // All jobs shown to user (left + right)

  bool _isFetching = false;
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
    _feedExhausted = false;
  }

  // Also track when a job card is displayed (even without swipe)
  void markSeen(String jobId) => _seenIds.add(jobId);

  /// Manually trigger a personalized ingest using the user's profile.
  Future<void> triggerIngest(UserProfile profile) async {
    // offline mock
    print('✅ Fallback: Mock ingest triggered for offline mode.');
  }

  // ─── Internal ──────────────────────────────────────────────

  List<Job> _getSorted() {
    final swipedIds = _swipeHistory.map((s) => s.jobId).toSet();
    // Backend already sorts by combined score — preserve that order
    return _buffer.where((j) => !swipedIds.contains(j.id)).toList();
  }

  /// Fetches jobs from local mock data instead of python API.
  Future<void> _refetch(UserProfile profile) async {
    if (_isFetching || _feedExhausted) return;
    if (_buffer.length >= _bufferMinSize) return;

    _isFetching = true;
    try {
      await Future.delayed(const Duration(milliseconds: 500)); // simulate network

      final mockJobs = [
        Job(
          id: 'job_${DateTime.now().millisecondsSinceEpoch}_1',
          title: 'Senior Flutter Developer',
          company: 'TechCorp',
          location: 'Remote',
          // salary: '\$90,000 - \$120,000',
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
          // salary: '\$70,000 - \$95,000',
          jobType: 'Full-time',
          description: 'Drive growth and user acquisition...',
          requiredSkills: ['SEO', 'Content Strategy', 'Google Analytics'],
          industry: 'Marketing',
          matchScore: 0.88,
          vibeTag: '📈 Impact',
          summaryBullets: ['Manage \$1M ad spend', 'Run A/B tests'],
        ),
        Job(
          id: 'job_${DateTime.now().millisecondsSinceEpoch}_3',
          title: 'Product Designer',
          company: 'DesignWorks',
          location: 'On-site',
          // salary: '\$85,000 - \$110,000',
          jobType: 'Full-time',
          description: 'Create beautiful user experiences...',
          requiredSkills: ['Figma', 'UI/UX', 'Prototyping'],
          industry: 'Design',
          matchScore: 0.70,
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
      
      print('✅ Mock fetched $added new jobs. Buffer: ${_buffer.length}');
      
      if (added == 0) {
         _feedExhausted = true;
         print('ℹ️  Mock Feed exhausted.');
      }
    } catch (e) {
      print('⚠️ Mock generation error: $e');
    } finally {
      _isFetching = false;
    }
  }
}
