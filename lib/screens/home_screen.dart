import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../app_theme.dart';
import '../models/job.dart';
import '../models/swipe_action.dart';
import '../services/cv_generation_service.dart';
import '../services/job_recommendation_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/job_card.dart';

// ============================================================
// SCREEN: HomeScreen — Browse (Main Swipe Screen)
// Tinder-style swipe with gold glassmorphism design
//
// Queue Pagination (v2.1):
//  • 60s periodic timer: fires every 60 seconds; triggers a background
//    queue update ONLY if the user has actively swiped since the last fetch.
//  • 5-swipe trigger: the service also self-triggers after every 5 swipes.
//  • Append-only: new jobs are appended to the BOTTOM of _jobs list.
//    The CardSwiper index is never reset — the current card is undisturbed.
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final JobRecommendationService _recService = JobRecommendationService();
  final CVGenerationService _cvService = CVGenerationService();
  final CardSwiperController _swiperController = CardSwiperController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  List<Job> _jobs = [];
  bool _isLoading = true;

  // ── 60-second Queue Refresh Timer ─────────────────────────────────
  Timer? _queueTimer;

  @override
  void initState() {
    super.initState();

    // Register the append-only callback: called by the service when background
    // queue updates return new jobs. Appends to BOTTOM of deck, never resets index.
    _recService.setOnQueueUpdate(_onQueueUpdateReceived);

    // Load initial job feed
    _loadJobs();

    // ── Start 60-second periodic timer ────────────────────────────────
    // On each tick: delegates to service which checks if user is active
    // (has swiped at least once since last fetch) before fetching.
    _queueTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (!mounted) return;
        final profile = context.read<UserProfileService>().profile;
        _recService.triggerTimedQueueUpdate(profile);
      },
    );
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    _swiperController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  // ─── Initial Load ────────────────────────────────────────────

  void _loadJobs() {
    setState(() => _isLoading = true);
    final profile = context.read<UserProfileService>().profile;
    _recService.getRecommendedJobsAsync(profile).then((jobs) {
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _jobs = _recService.getRecommendedJobs(profile);
          _isLoading = false;
        });
      }
    });
  }

  // ─── Append-Only Queue Update Callback ───────────────────────
  //
  // This is the KEY zero-interruption mechanism:
  //  • Called by JobRecommendationService when a background fetch completes.
  //  • New jobs are appended to the END of _jobs (not inserted at index 0).
  //  • CardSwiper's current card index is determined by what has already been
  //    swiped away — appending to the tail never affects the active card.
  //  • setState() rebuilds the card count but the swiper preserves its position.

  void _onQueueUpdateReceived(List<Job> freshJobs) {
    if (!mounted) return;
    if (freshJobs.isEmpty) return;

    setState(() {
      // Only append jobs that are not already in the deck (dedup guard)
      final existingIds = _jobs.map((j) => j.id).toSet();
      final toAppend = freshJobs.where((j) => !existingIds.contains(j.id)).toList();
      _jobs = [..._jobs, ...toAppend]; // APPEND to bottom — never prepend or replace
      debugPrint('📥 [HomeScreen] Appended ${toAppend.length} jobs to deck bottom. '
          'Total deck: ${_jobs.length}');
    });
  }

  // ─── Deck End Handler ────────────────────────────────────────

  /// Called when CardSwiper reaches the last card (onEnd).
  /// Only shows empty state if the feed is truly exhausted server-side.
  void _onDeckEnd() {
    final profile = context.read<UserProfileService>().profile;
    if (_recService.isFeedExhausted) {
      setState(() {
        _jobs = [];
        _isLoading = false;
      });
      return;
    }
    // Try to get any remaining buffer jobs (may have been appended already)
    final buffered = _recService.getRecommendedJobs(profile);
    if (buffered.isNotEmpty) {
      setState(() => _jobs = buffered);
      return;
    }
    // Trigger a fresh fetch; show loading until results arrive
    setState(() {
      _isLoading = true;
      _jobs = [];
    });
    _recService.getRecommendedJobsAsync(profile).then((jobs) {
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
      }
    });
  }

  // ─── Swipe Handlers ──────────────────────────────────────────

  bool _onSwipe(int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (previousIndex >= _jobs.length) return true;
    final job = _jobs[previousIndex];
    if (direction == CardSwiperDirection.right) {
      _handleSwipeRight(job);
    } else if (direction == CardSwiperDirection.left) {
      _handleSwipeLeft(job);
    }
    _scrollOffset.value = 0;
    return true;
  }

  void _handleSwipeLeft(Job job) {
    final profile = context.read<UserProfileService>().profile;
    _recService.recordSwipe(
      SwipeAction(
        id: 'sw_${DateTime.now().millisecondsSinceEpoch}',
        jobId: job.id,
        jobTitle: job.title,
        company: job.company,
        direction: SwipeDirection.left,
      ),
      profile, // ← passed to trigger queue update checks
    );
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('👎  Passed on ${job.title}', style: GoogleFonts.outfit()),
        backgroundColor: const Color(0xAAD32F2F),
        duration: const Duration(milliseconds: 1200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));
  }

  Future<void> _handleSwipeRight(Job job) async {
    final profile = context.read<UserProfileService>().profile;
    _recService.recordSwipe(
      SwipeAction(
        id: 'sw_${DateTime.now().millisecondsSinceEpoch}',
        jobId: job.id,
        jobTitle: job.title,
        company: job.company,
        direction: SwipeDirection.right,
      ),
      profile, // ← passed to trigger queue update checks
    );

    // ── Step 1: Save job to Matches immediately ─────────────────────
    final appState = context.read<AppState>();
    appState.addMatchWithoutCV(job);

    // Show a quick confirmation snackbar
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✦', style: TextStyle(color: kGold, fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Saved! Generating your tailored CV…',
                style: GoogleFonts.outfit(color: kGoldLight),
              ),
            ),
          ]),
          backgroundColor: const Color(0xAA1A1200),
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
    }

    // ── Step 2: Generate CV in background ──────────────────────────
    try {
      final cv = await _cvService.generateCV(job: job, profile: profile);
      if (mounted) {
        // Attach CV to the already-saved match
        appState.updateCV(job.id, cv);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CV ready for ${job.title} — view in Matches tab!',
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
              ),
            ]),
            backgroundColor: const Color(0xFF1B3A2B),
            duration: const Duration(seconds: 4),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ));
      }
    } catch (e) {
      // Job is already saved — CV can be generated later from the Matches tab
      if (mounted) {
        debugPrint('Background CV generation failed: $e');
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          Expanded(
              child: _isLoading
                  ? _buildLoading()
                  : _jobs.isEmpty
                      ? _buildEmpty()
                      : _buildSwipeArea()),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title
          Row(
            children: [
              Image.asset('assets/images/app_logo.png', width: 36, height: 36),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Browse', style: kHeadline(26)),
                Consumer<UserProfileService>(
                  builder: (_, svc, __) => Text(
                    svc.profile.careerFields.isNotEmpty
                        ? 'Matched to: ${svc.profile.careerFields.first}'
                        : 'RECOMMENDED',
                    style: kLabel(11, color: kGoldDim),
                  ),
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeArea() {
    return Stack(children: [
      // Card stack
      Column(children: [
        // Jobs remaining indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('${_jobs.length} listings',
                  style: kBody(12, color: kGoldDim, opacity: 0.7)),
            ],
          ),
        ),

        Expanded(
          child: CardSwiper(
            controller: _swiperController,
            cardsCount: _jobs.length,
            onSwipe: _onSwipe,
            onEnd: _onDeckEnd,
            isLoop: false, // CRITICAL: prevents cycle
            numberOfCardsDisplayed: _jobs.length < 3 ? _jobs.length : 3,
            backCardOffset: const Offset(0, -18),
            scale: 0.93,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            cardBuilder: (ctx, index, hPct, vPct) {
              if (index >= _jobs.length) return const SizedBox.shrink();
              return ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (_, scrollOffset, __) {
                  final hideOverlay = scrollOffset > 50;
                  return Stack(children: [
                    JobCard(
                      job: _jobs[index],
                      scrollNotifier: index == 0 ? _scrollOffset : null,
                      onSwipeLeft: () =>
                          _swiperController.swipe(CardSwiperDirection.left),
                      onSwipeRight: () =>
                          _swiperController.swipe(CardSwiperDirection.right),
                    ),
                    // APPLY overlay
                    if (!hideOverlay && hPct > 20)
                      _swipeOverlay('✓', kGold, true),
                    // PASS overlay
                    if (!hideOverlay && hPct < -20)
                      _swipeOverlay('✗', const Color(0xFFE0E0E0), false),
                  ]);
                },
              );
            },
          ),
        ),
      ]),
    ]);
  }

  Widget _swipeOverlay(String icon, Color color, bool isRight) {
    return Positioned(
      top: 60,
      left: isRight ? 40 : null,
      right: isRight ? null : 40,
      child: Transform.rotate(
        angle: isRight ? -0.2 : 0.2,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 8,
              )
            ],
          ),
          child: Text(icon,
              style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: color.withValues(alpha: 0.8), blurRadius: 16)
                  ])),
        ).animate(onPlay: (controller) => controller.repeat(reverse: true))
         .shimmer(duration: 1000.ms, color: Colors.white.withValues(alpha: 0.3)),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: kGold, strokeWidth: 2),
        const SizedBox(height: 20),
        Text('Finding your matches…', style: kHeadline(18)),
        const SizedBox(height: 8),
        Text('Querying the AI feed', style: kBody(13, opacity: 0.5)),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('✦', style: TextStyle(fontSize: 52, color: kGold)),
        const SizedBox(height: 16),
        Text("You've seen all listings!", style: kHeadline(22)),
        const SizedBox(height: 8),
        Text('New roles are loaded every 30 min',
            style: kBody(14, opacity: 0.5)),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: _loadJobs,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(color: kGold.withValues(alpha: 0.3), blurRadius: 16)
              ],
            ),
            child: Text('Refresh Feed',
                style: GoogleFonts.outfit(
                    color: kBg1, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
