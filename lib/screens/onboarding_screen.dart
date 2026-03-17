import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import 'sign_in_screen.dart';

// ============================================================
// SCREEN: OnboardingScreen
// 4-page carousel introducing Kindred Careers.
// Gold/glassmorphism aesthetic matching the rest of the app.
// ============================================================

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      emoji: '✦',
      title: 'Welcome to\nKindred Careers',
      subtitle:
          'The job search app built for the age of AI.\nFind roles that truly match who you are.',
      glowColor: Color(0xFFC9A84C),
    ),
    _OnboardingPage(
      emoji: '👆',
      title: 'Swipe Your\nWay to Work',
      subtitle:
          'Browse curated job listings with a swipe.\nRight to apply, left to pass — it\'s that simple.',
      glowColor: Color(0xFF0D9F8F),
    ),
    _OnboardingPage(
      emoji: '🧠',
      title: 'AI-Powered\nMatching',
      subtitle:
          'Our engine reads your skills, experience, and\npreferences — then ranks every listing for you.',
      glowColor: Color(0xFF6B3DA6),
    ),
    _OnboardingPage(
      emoji: '📄',
      title: 'Tailored CVs,\nInstantly',
      subtitle:
          'Swipe right and we\'ll generate a custom CV\nperfectly crafted for that exact role.',
      glowColor: Color(0xFFC9A84C),
    ),
  ];

  void _next() {
    if (_currentPage < _pages.length - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    } else {
      _goToSignIn();
    }
  }

  void _goToSignIn() async {
    // Mark onboarding as seen so it doesn't show again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // Background gradient + glows
        _OnboardingBackground(glowColor: _pages[_currentPage].glowColor),

        SafeArea(
          child: Column(children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _goToSignIn,
                child: Text('Skip',
                    style: GoogleFonts.outfit(color: kGoldDim, fontSize: 14)),
              ),
            ),

            // Page view (fills remaining space)
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (ctx, i) => _buildPageContent(_pages[i], i),
              ),
            ),

            // Page indicators + CTA button
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
              child: Column(children: [
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _currentPage ? 24 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _currentPage
                            ? kGold
                            : kGoldDim.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // CTA button
                GestureDetector(
                  onTap: _next,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    decoration: BoxDecoration(
                      gradient: kGoldGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                            color: kGold.withOpacity(0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 8))
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Get Started  →'
                            : 'Next  →',
                        style: GoogleFonts.outfit(
                          color: kBg1,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPageContent(_OnboardingPage page, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji icon in a glass circle
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: kGlassBg,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: kGoldDim.withOpacity(0.4), width: 1.5),
                ),
                child: Center(
                  child: Text(page.emoji, style: const TextStyle(fontSize: 52)),
                ),
              ),
            ),
          )
              .animate(key: ValueKey(index))
              .fadeIn(duration: 400.ms, delay: 100.ms)
              .scale(begin: const Offset(0.8, 0.8), duration: 400.ms),

          const SizedBox(height: 36),

          Text(
            page.title,
            style: GoogleFonts.outfit(
              color: kCream,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('t$index'))
              .fadeIn(duration: 400.ms, delay: 200.ms)
              .slideY(begin: 0.2, duration: 400.ms),

          const SizedBox(height: 18),

          Text(
            page.subtitle,
            style: GoogleFonts.outfit(
              color: kCream.withOpacity(0.6),
              fontSize: 15,
              height: 1.7,
            ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('s$index'))
              .fadeIn(duration: 400.ms, delay: 300.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Data class for a single onboarding page
// ─────────────────────────────────────────────────────────────

class _OnboardingPage {
  final String emoji;
  final String title;
  final String subtitle;
  final Color glowColor;
  const _OnboardingPage(
      {required this.emoji,
      required this.title,
      required this.subtitle,
      required this.glowColor});
}

// ─────────────────────────────────────────────────────────────
// Animated background that shifts glow color per page
// ─────────────────────────────────────────────────────────────

class _OnboardingBackground extends StatelessWidget {
  final Color glowColor;
  const _OnboardingBackground({required this.glowColor});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: kBackgroundGradient),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          child: Stack(children: [
            Positioned(
              top: -80,
              right: -80,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    glowColor.withOpacity(0.2),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF2D1B5E).withOpacity(0.3),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
