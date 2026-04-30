import 'dart:ui';
import 'package:flutter/foundation.dart';
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

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  @override
  void dispose() {
    _swiperController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

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

  /// Called when CardSwiper reaches the last card (onEnd).
  /// Tries to load a fresh batch from the backend. If none remain, shows empty state.
  void _onDeckEnd() {
    final profile = context.read<UserProfileService>().profile;
    if (_recService.isFeedExhausted) {
      // Backend told us there are no more unseen jobs
      setState(() {
        _jobs = [];
        _isLoading = false;
      });
      return;
    }
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

  bool _onSwipe(
      int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (previousIndex >= _jobs.length) return true;
    final job = _jobs[previousIndex];
    if (direction == CardSwiperDirection.right) {
      _handleSwipeRight(job);
    } else if (direction == CardSwiperDirection.left) _handleSwipeLeft(job);
    _scrollOffset.value = 0;
    return true;
  }

  void _handleSwipeLeft(Job job) {
    _recService.recordSwipe(SwipeAction(
      id: 'sw_${DateTime.now().millisecondsSinceEpoch}',
      jobId: job.id,
      jobTitle: job.title,
      company: job.company,
      direction: SwipeDirection.left,
    ));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content:
            Text('👎  Passed on ${job.title}', style: GoogleFonts.outfit()),
        backgroundColor: const Color(0xAAD32F2F),
        duration: const Duration(milliseconds: 1200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));
  }

  Future<void> _handleSwipeRight(Job job) async {
    _recService.recordSwipe(SwipeAction(
      id: 'sw_${DateTime.now().millisecondsSinceEpoch}',
      jobId: job.id,
      jobTitle: job.title,
      company: job.company,
      direction: SwipeDirection.right,
    ));

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
    final profile = context.read<UserProfileService>().profile;
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
            onEnd: _onDeckEnd, // ← fires when last card is swiped
            isLoop: false, // ← CRITICAL: prevents cycle
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
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
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
                    Shadow(color: color.withOpacity(0.8), blurRadius: 16)
                  ])),
        ).animate(onPlay: (controller) => controller.repeat(reverse: true))
         .shimmer(duration: 1000.ms, color: Colors.white.withOpacity(0.3)),
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
                BoxShadow(color: kGold.withOpacity(0.3), blurRadius: 16)
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
