import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../config/demo_config.dart';
import '../services/mock/mock_auth_service.dart';
import '../utils/demo_typing_controller.dart';

// Conditional import for live mode
import '../services/auth_service.dart';

// ============================================================
// SCREEN: SignInScreen
// Firebase email/password + Google Sign-In (Live Mode)
// + 3-Member Demo Persona Tabs (Demo Mode)
// Matches the gold/glassmorphism aesthetic of the app.
// ============================================================

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _signInKey = GlobalKey<FormState>();
  final _signUpKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _email2Ctrl = TextEditingController();
  final _password2Ctrl = TextEditingController();

  bool _obscureSignIn = true;
  bool _obscureSignUp = true;
  bool _isLoading = false;
  String? _errorMsg;

  // Demo mode: which member tab is selected (-1 = none)
  int _selectedDemoMember = -1;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() => _errorMsg = null));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in [
      _emailCtrl,
      _passwordCtrl,
      _nameCtrl,
      _email2Ctrl,
      _password2Ctrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Demo Mode: Sign in as mock member ──────────────────────
  Future<void> _demoSignIn(int memberIndex) async {
    setState(() {
      _selectedDemoMember = memberIndex;
      _isLoading = true;
      _errorMsg = null;
    });

    // Auto-fill email + password with typing animation
    final member = DemoConfig.members[memberIndex - 1];
    await DemoTypingController.typeInto(_emailCtrl, member['email']!);
    await Future.delayed(const Duration(milliseconds: 150));
    await DemoTypingController.typeInto(_passwordCtrl, member['password']!);
    await Future.delayed(const Duration(milliseconds: 300));

    // Sign in with mock auth
    MockAuthService.signInAsMember(memberIndex);

    if (mounted) {
      setState(() => _isLoading = false);
      // Navigate to the demo auth gate (which routes to questionnaire/main)
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  Future<void> _signIn() async {
    if (DemoConfig.isDemoMode) return; // Guard: never use Firebase in demo
    if (!_signInKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final err =
        await AuthService.signInWithEmail(_emailCtrl.text, _passwordCtrl.text);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMsg = err;
      });
    }
    // Navigation handled by StreamBuilder in main.dart
  }

  Future<void> _signUp() async {
    if (DemoConfig.isDemoMode) return;
    if (!_signUpKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final err = await AuthService.signUpWithEmail(
        _email2Ctrl.text, _password2Ctrl.text, _nameCtrl.text);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMsg = err;
      });
    }
  }

  Future<void> _googleSignIn() async {
    if (DemoConfig.isDemoMode) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final err = await AuthService.signInWithGoogle();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMsg = err;
      });
    }
  }

  Future<void> _forgotPassword() async {
    if (DemoConfig.isDemoMode) return;
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Enter your email above first.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    final err = await AuthService.sendPasswordReset(_emailCtrl.text);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      if (err == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✦ Reset email sent!',
              style: GoogleFonts.outfit(color: kGoldLight)),
          backgroundColor: const Color(0xAA1A1200),
        ));
      } else {
        setState(() => _errorMsg = err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // Background
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: kBackgroundGradient),
            child: Stack(children: [
              Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                      width: 320,
                      height: 320,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            const Color(0xFFC9A84C).withOpacity(0.12),
                            Colors.transparent
                          ])))),
              Positioned(
                  bottom: -80,
                  left: -80,
                  child: Container(
                      width: 280,
                      height: 280,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            const Color(0xFF2D1B5E).withOpacity(0.25),
                            Colors.transparent
                          ])))),
            ]),
          ),
        ),

        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(children: [
              const SizedBox(height: 20),

              // ── Logo / Brand ──
              Column(children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: kGold.withOpacity(0.3), blurRadius: 20)
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Kindred Careers', style: kHeadline(26)),
                const SizedBox(height: 6),
                Text(
                  DemoConfig.isDemoMode
                      ? 'Select a demo persona below'
                      : 'Sign in to find your perfect role',
                  style: kBody(14, opacity: 0.5),
                ),
              ]).animate().fadeIn(duration: 500.ms).slideY(begin: -0.1),

              const SizedBox(height: 32),

              // ── Google Sign-In (hidden in demo mode) ──
              if (!DemoConfig.isDemoMode) ...[
                GestureDetector(
                  onTap: _isLoading ? null : _googleSignIn,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: kGlassBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kGoldDim.withOpacity(0.35)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('G',
                                  style: TextStyle(
                                      color: kGold,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 10),
                              Text('Continue with Google',
                                  style: GoogleFonts.outfit(
                                      color: kCream,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ),
                  ),
                ).animate().fadeIn(duration: 500.ms, delay: 150.ms),

                const SizedBox(height: 20),

                // ── Divider ──
                Row(children: [
                  Expanded(child: Divider(color: kGoldDim.withOpacity(0.2))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: kBody(13, opacity: 0.4)),
                  ),
                  Expanded(child: Divider(color: kGoldDim.withOpacity(0.2))),
                ]),

                const SizedBox(height: 20),
              ],

              // ── Tab: Sign In / Sign Up ──
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: glassCard(borderRadius: 22),
                    child: Column(children: [
                      // Tab bar
                      Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kGlassBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: TabBar(
                          controller: _tabCtrl,
                          indicatorSize: TabBarIndicatorSize.tab,
                          indicator: BoxDecoration(
                            gradient: kGoldGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelStyle: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700, fontSize: 14),
                          unselectedLabelColor: kGoldDim,
                          labelColor: kBg1,
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Sign In'),
                            Tab(text: 'Sign Up'),
                          ],
                        ),
                      ),

                      // Error banner
                      if (_errorMsg != null)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    const Color(0xFFFF5252).withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: Color(0xFFFF5252), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_errorMsg!,
                                    style: GoogleFonts.outfit(
                                        color: const Color(0xFFFF5252),
                                        fontSize: 12))),
                          ]),
                        ),

                      // Tab content
                      SizedBox(
                        height: 280,
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: [
                            _buildSignInForm(),
                            _buildSignUpForm(),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ).animate().fadeIn(duration: 500.ms, delay: 250.ms),

              // ── Demo Mode: 3-Member Persona Tabs ──────────────
              if (DemoConfig.isDemoMode) ...[
                const SizedBox(height: 24),
                _buildDemoMemberTabs(),
              ],
            ]),
          ),
        ),

        // Loading overlay
        if (_isLoading)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  color: Colors.black38,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: kGold, strokeWidth: 3)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ── Demo Member Tabs ───────────────────────────────────────
  Widget _buildDemoMemberTabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEMO ACCESS', style: kLabel(11, color: kGoldDim)),
        const SizedBox(height: 10),
        Row(
          children: List.generate(3, (i) {
            final member = DemoConfig.members[i];
            final isSelected = _selectedDemoMember == (i + 1);
            return Expanded(
              child: GestureDetector(
                onTap: _isLoading ? null : () => _demoSignIn(i + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: isSelected ? kGoldGradient : null,
                    color: isSelected ? null : kGlassBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? kGold : kGoldDim.withOpacity(0.4),
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: kGold.withOpacity(0.3), blurRadius: 12)]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        member['emoji']!,
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member['label']!.split(' (').first, // e.g. "Member 1"
                        style: GoogleFonts.outfit(
                          color: isSelected ? kBg1 : kCream.withOpacity(0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        '(${member['label']!.split('(').last}', // e.g. "(AI)"
                        style: GoogleFonts.outfit(
                          color: isSelected ? kBg1.withOpacity(0.7) : kGoldDim,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    ).animate().fadeIn(duration: 500.ms, delay: 400.ms).slideY(begin: 0.1);
  }

  // ── Sign In Form ────────────────────────────────────────────
  Widget _buildSignInForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Form(
        key: _signInKey,
        child: Column(children: [
          _field(_emailCtrl, 'Email', Icons.email_outlined,
              type: TextInputType.emailAddress,
              validator: (v) =>
                  v!.contains('@') ? null : 'Enter a valid email'),
          const SizedBox(height: 10),
          _field(_passwordCtrl, 'Password', Icons.lock_outline,
              obscure: _obscureSignIn,
              toggleObscure: () =>
                  setState(() => _obscureSignIn = !_obscureSignIn),
              validator: (v) => v!.length >= 6 ? null : 'Min 6 characters'),
          const SizedBox(height: 4),
          if (!DemoConfig.isDemoMode)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                child:
                    Text('Forgot password?', style: kLabel(11, color: kGoldDim)),
              ),
            ),
          const SizedBox(height: 12),
          _goldButton(
            DemoConfig.isDemoMode ? 'Select a Member Below ↓' : 'Sign In',
            DemoConfig.isDemoMode ? () {} : _signIn,
          ),
        ]),
      ),
    );
  }

  // ── Sign Up Form ────────────────────────────────────────────
  Widget _buildSignUpForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Form(
        key: _signUpKey,
        child: Column(children: [
          _field(_nameCtrl, 'Full Name', Icons.person_outline,
              validator: (v) =>
                  v!.trim().isNotEmpty ? null : 'Enter your name'),
          const SizedBox(height: 10),
          _field(_email2Ctrl, 'Email', Icons.email_outlined,
              type: TextInputType.emailAddress,
              validator: (v) =>
                  v!.contains('@') ? null : 'Enter a valid email'),
          const SizedBox(height: 10),
          _field(_password2Ctrl, 'Password (6+ chars)', Icons.lock_outline,
              obscure: _obscureSignUp,
              toggleObscure: () =>
                  setState(() => _obscureSignUp = !_obscureSignUp),
              validator: (v) => v!.length >= 6 ? null : 'Min 6 characters'),
          const SizedBox(height: 14),
          _goldButton(
            DemoConfig.isDemoMode ? 'Select a Member Below ↓' : 'Create Account',
            DemoConfig.isDemoMode ? () {} : _signUp,
          ),
        ]),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
    bool obscure = false,
    VoidCallback? toggleObscure,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      style: kBody(14),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: kBody(13, opacity: 0.3),
        prefixIcon: Icon(icon, color: kGoldDim, size: 18),
        suffixIcon: toggleObscure != null
            ? IconButton(
                icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: kGoldDim,
                    size: 18),
                onPressed: toggleObscure)
            : null,
        filled: true,
        fillColor: kGlassBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.25))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGold, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF5252))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF5252), width: 1.5)),
      ),
    );
  }

  Widget _goldButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: DemoConfig.isDemoMode ? null : kGoldGradient,
          color: DemoConfig.isDemoMode ? kGlassBg : null,
          borderRadius: BorderRadius.circular(14),
          border: DemoConfig.isDemoMode
              ? Border.all(color: kGoldDim.withOpacity(0.3))
              : null,
          boxShadow: DemoConfig.isDemoMode
              ? null
              : [BoxShadow(color: kGold.withOpacity(0.3), blurRadius: 16)],
        ),
        child: Center(
            child: Text(label,
                style: GoogleFonts.outfit(
                    color: DemoConfig.isDemoMode ? kGoldDim : kBg1,
                    fontSize: 15,
                    fontWeight: FontWeight.w800))),
      ),
    );
  }
}
