import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/questionnaire_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/matched_jobs_screen.dart';
import 'services/user_profile_service.dart';
import 'services/cv_generation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // ── Initialize Firebase ─────────────────────────────────────
  // Uses the native google-services.json added to the android/app/ folder.
  await Firebase.initializeApp();

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
    return MaterialApp(
      title: 'Kindred Careers',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Named route so QuestionnaireScreen can push to /main after submit
      routes: {
        '/main': (_) => const MainShell(),
      },
      home: showOnboarding ? const OnboardingScreen() : const _AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// AUTH GATE — listens to Firebase auth state and routes accordingly
// ─────────────────────────────────────────────────────────────
class _AuthGate extends StatelessWidget {
  const _AuthGate();

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
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildNavBar() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Container(
          decoration: BoxDecoration(
            color: kBg1.withOpacity(0.85),
            border: Border(
              top: BorderSide(color: kGoldDim.withOpacity(0.3), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(0, Icons.person_outline_rounded,
                      Icons.person_rounded, 'Profile'),
                  _navItem(
                      1, Icons.layers_outlined, Icons.layers_rounded, 'Browse'),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? kGoldGradient : null,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? kBg1 : kGoldDim,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive ? kBg1 : kGoldDim,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? kGoldGradient : null,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? kBg1 : kGoldDim,
                  size: 22,
                ),
                if (count > 0)
                  Positioned(
                    top: -5,
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
                color: isActive ? kBg1 : kGoldDim,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
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
            // Subtle teal glow top-right
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
                      const Color(0xFF0D4F6B).withOpacity(0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Subtle purple glow bottom-left
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
                      const Color(0xFF2D1B5E).withOpacity(0.3),
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
