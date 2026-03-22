import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/job.dart';
import '../models/swipe_action.dart';
import '../services/cv_generation_service.dart';
import '../services/job_recommendation_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/cv_preview_dialog.dart';
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
  bool _isCVGenerating = false;

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
      if (mounted)
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
    }).catchError((_) {
      if (mounted)
        setState(() {
          _jobs = _recService.getRecommendedJobs(profile);
          _isLoading = false;
        });
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
      if (mounted)
        setState(() {
          _jobs = jobs;
          _isLoading = false;
        });
    });
  }

  bool _onSwipe(
      int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (previousIndex >= _jobs.length) return true;
    final job = _jobs[previousIndex];
    if (direction == CardSwiperDirection.right)
      _handleSwipeRight(job);
    else if (direction == CardSwiperDirection.left) _handleSwipeLeft(job);
    _scrollOffset.value = 0;
    // Remove swiped job so listing count stays accurate
    // (CardSwiper already moved past it — cosmetic update only)
    Future.microtask(() {
      if (mounted && previousIndex < _jobs.length) {
        setState(() => _jobs.removeAt(previousIndex));
      }
    });
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
    setState(() {
      _isCVGenerating = true;
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
          const SizedBox(width: 12),
          Text('✦  Crafting your tailored CV…',
              style: GoogleFonts.outfit(color: kGoldLight)),
        ]),
        backgroundColor: const Color(0xAA1A1200),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));

    final profile = context.read<UserProfileService>().profile;
    try {
      final cv = await _cvService.generateCV(job: job, profile: profile);
      if (mounted) {
        setState(() => _isCVGenerating = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) =>
              CVPreviewDialog(job: job, initialCV: cv, isNewMatch: true),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCVGenerating = false);
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
            isLoop: false, // ← CRITICAL: prevents cycling
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
                      _swipeOverlay('APPLY ✓', const Color(0xFF4CAF50), true),
                    // PASS overlay
                    if (!hideOverlay && hPct < -20)
                      _swipeOverlay('PASS ✗', const Color(0xFFFF5252), false),
                  ]);
                },
              );
            },
          ),
        ),

        // Action buttons
        _buildActionButtons(),
      ]),

      // CV generating full-screen overlay
      if (_isCVGenerating)
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: kGold, strokeWidth: 3),
                  const SizedBox(height: 20),
                  Text('Crafting your CV…', style: kHeadline(18)),
                  const SizedBox(height: 8),
                  Text('Tailored by AI to match this role',
                      style: kBody(14, opacity: 0.6)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _swipeOverlay(String label, Color color, bool isRight) {
    return Positioned(
      top: 40,
      left: isRight ? 20 : null,
      right: isRight ? null : 20,
      child: Transform.rotate(
        angle: isRight ? -0.2 : 0.2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 3),
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.2), blurRadius: 12)
            ],
          ),
          child: Text(label,
              style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(color: color.withOpacity(0.5), blurRadius: 8)
                  ])),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 100),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionBtn(Icons.close_rounded, const Color(0xFFFF5252), 56,
              () => _swiperController.swipe(CardSwiperDirection.left)),
          _actionBtn(Icons.star_outline_rounded, kGold, 44, () {}),
          _actionBtn(Icons.check_rounded, const Color(0xFF4CAF50), 56,
              () => _swiperController.swipe(CardSwiperDirection.right)),
        ],
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, Color color, double size, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kBg2.withOpacity(0.7),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 14)],
        ),
        child: Icon(icon, color: color, size: size * 0.45),
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
