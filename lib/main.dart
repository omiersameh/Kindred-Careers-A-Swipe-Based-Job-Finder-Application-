import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'config/demo_config.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/questionnaire_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/matched_jobs_screen.dart';
import 'services/user_profile_service.dart';
import 'services/cv_generation_service.dart';
import 'services/mock/mock_auth_service.dart';

// Conditional imports: only used when NOT in demo mode
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'utils/banner_selector.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Demo Mode: skip Firebase + dotenv entirely ──────────────
  if (!DemoConfig.isDemoMode) {
    await dotenv.load(fileName: ".env");
    await BannerSelector.init();
    await Firebase.initializeApp();
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // ── Check first-launch flag (show onboarding once) ──────────
  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProfileService()),
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: KindredCareersApp(showOnboarding: !seenOnboarding),
    ),
  );
}

class KindredCareersApp extends StatelessWidget {
  final bool showOnboarding;
  const KindredCareersApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    // ── Demo Mode: no Firebase Analytics, use DemoAuthGate ────
    if (DemoConfig.isDemoMode) {
      return MaterialApp(
        title: 'Kindred Careers (Demo)',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routes: {
          '/main': (_) => const MainShell(),
          '/auth': (_) => const DemoAuthGate(),
        },
        builder: (context, child) {
          return Banner(
            message: 'DEMO',
            location: BannerLocation.topEnd,
            color: kGold,
            textStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0D0B0A),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: showOnboarding ? const OnboardingScreen() : const DemoAuthGate(),
      );
    }

    // ── Live Mode: unchanged behavior ────────────────────────
    try {
      FirebaseAnalytics analytics = FirebaseAnalytics.instance;
      return MaterialApp(
        title: 'Kindred Careers',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        navigatorObservers: [
          FirebaseAnalyticsObserver(analytics: analytics),
        ],
        routes: {
          '/main': (_) => const MainShell(),
          '/auth': (_) => const AuthGate(),
        },
        home: showOnboarding ? const OnboardingScreen() : const AuthGate(),
      );
    } catch (_) {
      // Fallback if analytics errors out
      return MaterialApp(
        title: 'Kindred Careers',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routes: {
          '/main': (_) => const MainShell(),
          '/auth': (_) => const AuthGate(),
        },
        home: showOnboarding ? const OnboardingScreen() : const AuthGate(),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// DEMO AUTH GATE — bypasses Firebase, routes based on MockAuthService
// ─────────────────────────────────────────────────────────────
class DemoAuthGate extends StatelessWidget {
  const DemoAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // If a mock user is already signed in, go to post-auth routing
    if (MockAuthService.isSignedIn) {
      return const _DemoPostAuthRouter();
    }
    // Otherwise show the sign-in screen (which has demo member tabs)
    return const SignInScreen();
  }
}

// ─────────────────────────────────────────────────────────────
// DEMO POST-AUTH ROUTER — checks if questionnaire is complete
// ─────────────────────────────────────────────────────────────
class _DemoPostAuthRouter extends StatefulWidget {
  const _DemoPostAuthRouter();

  @override
  State<_DemoPostAuthRouter> createState() => _DemoPostAuthRouterState();
}

class _DemoPostAuthRouterState extends State<_DemoPostAuthRouter> {
  bool _loading = true;
  bool _questionnaireDone = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final uid = MockAuthService.currentUser?.uid ?? 'demo_guest';
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('questionnaire_done_$uid') ?? false;
    
    if (mounted) {
      await context.read<UserProfileService>().loadProfile();
      setState(() { _questionnaireDone = done; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBg1,
        body: Center(child: CircularProgressIndicator(color: kGold, strokeWidth: 3)),
      );
    }
    return _questionnaireDone ? const MainShell() : const QuestionnaireScreen();
  }
}

// ─────────────────────────────────────────────────────────────
// AUTH GATE — listens to Firebase auth state and routes accordingly
// (Only used in Live Mode)
// ─────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still connecting to Firebase
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: kBg1,
            body: Center(
              child: CircularProgressIndicator(color: kGold, strokeWidth: 3),
            ),
          );
        }
        // Signed in → check if questionnaire is complete
        if (snapshot.hasData && snapshot.data != null) {
          return const _PostAuthRouter();
        }
        // Not signed in → sign-in screen
        return const SignInScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// POST-AUTH ROUTER — checks if first-time user needs questionnaire
// (Only used in Live Mode)
// ─────────────────────────────────────────────────────────────
class _PostAuthRouter extends StatefulWidget {
  const _PostAuthRouter();

  @override
  State<_PostAuthRouter> createState() => _PostAuthRouterState();
}

class _PostAuthRouterState extends State<_PostAuthRouter> {
  bool _loading = true;
  bool _questionnaireDone = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('questionnaire_done_$uid') ?? false;
    
    if (mounted) {
      // Load the specific user's profile from storage into memory
      await context.read<UserProfileService>().loadProfile();
      setState(() { _questionnaireDone = done; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBg1,
        body: Center(child: CircularProgressIndicator(color: kGold, strokeWidth: 3)),
      );
    }
    return _questionnaireDone ? const MainShell() : const QuestionnaireScreen();
  }
}

// ============================================================
// WIDGET: MainShell — 3-tab navigation shell
// ============================================================

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 1;

  static const List<Widget> _screens = [
    ProfileScreen(),
    HomeScreen(),
    MatchedJobsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // ── Global background gradient (always visible) ──
          const _AppBackground(),
          // ── Screen content ──
          IndexedStack(index: _currentIndex, children: _screens),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _buildFloatingNavBar(),
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: kBg1.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(0, Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
                  _navItem(1, Icons.layers_outlined, Icons.layers_rounded, 'Browse'),
                  _navItemBadged(
                    2,
                    Icons.bookmark_border_rounded,
                    Icons.bookmark_rounded,
                    'Matches',
                    appState.matchedJobs.length,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? kGold : Colors.white70,
              size: 26,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? kGold : Colors.white70,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItemBadged(
      int index, IconData icon, IconData activeIcon, String label, int count) {
    final isActive = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? kGold : Colors.white70,
                  size: 26,
                ),
                if (count > 0)
                  Positioned(
                    top: -2,
                    right: -7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: kGold,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              fontSize: 8,
                              color: kBg1,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? kGold : Colors.white70,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Global background: deep navy/teal/purple gradient ─────────
class _AppBackground extends StatelessWidget {
  const _AppBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: kBackgroundGradient),
        child: Stack(
          children: [
            // Subtle gold glow top-right
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFC9A84C).withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Subtle gray glow bottom-left
            Positioned(
              bottom: -80,
              left: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFFFFFF).withValues(alpha: 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
