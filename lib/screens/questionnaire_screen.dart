import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../app_theme.dart';
import '../data/career_fields_data.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';

// ============================================================
// SCREEN: QuestionnaireScreen
// Forces new users to fill in their complete profile on first
// sign-up. 8-step wizard with a gold/glassmorphism aesthetic.
// Steps:
//  1. Name (first + last)
//  2. Location & Age
//  3. Education status + degree
//  4. Career fields (pick 1–3 from premade list)
//  5. Specializations per chosen field
//  6. Bio
//  7. Credentials / Certificates
//  8. Past Experiences / Workplaces
// ============================================================

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({super.key});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final PageController _pageCtrl = PageController();
  int _step = 0;
  static const int _totalSteps = 8;

  // ── Step 1: Name ────────────────────────────────────────────
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();

  // ── Step 2: Location & Contact ──────────────────────────────
  final _locationCtrl = TextEditingController();
  final _ageCtrl      = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = FirebaseAuth.instance.currentUser?.email ?? '';
  }

  // ── Step 3: Education ───────────────────────────────────────
  String _educationStatus = '';
  final _institutionCtrl  = TextEditingController();
  final _degreeCtrl       = TextEditingController();
  final _fieldOfStudyCtrl = TextEditingController();
  final _gradYearCtrl     = TextEditingController();

  static const _eduStatuses = [
    'High School',
    'Diploma',
    'Currently Enrolled (Undergraduate)',
    'Bachelor\'s Degree',
    'Currently Enrolled (Postgraduate)',
    'Master\'s Degree',
    'PhD / Doctorate',
    'Prefer not to say',
  ];

  // ── Step 4: Career Fields ───────────────────────────────────
  final Set<String> _selectedFieldIds = {};

  // ── Step 5: Specializations ─────────────────────────────────
  // fieldId → selected specializations (max 3 per field)
  final Map<String, Set<String>> _selectedSpecializations = {};

  // ── Step 6: Bio ─────────────────────────────────────────────
  final _bioCtrl = TextEditingController();

  // ── Step 7: Credentials ─────────────────────────────────────
  // Each credential: { title, issuer, year }
  final List<Map<String, String>> _credentials = [];

  // ── Step 8: Experience ──────────────────────────────────────
  // Handled as Experience objects
  final List<Experience> _experiences = [];

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl, _lastNameCtrl, _locationCtrl, _ageCtrl, _phoneCtrl, _emailCtrl,
      _institutionCtrl, _degreeCtrl, _fieldOfStudyCtrl, _gradYearCtrl,
      _bioCtrl,
    ]) { c.dispose(); }
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ───────────────────────────────────────────────
  void _next() {
    if (!_validateStep()) return;
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  bool _validateStep() {
    switch (_step) {
      case 0:
        if (_firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty) {
          _snack('Please enter your first and last name.');
          return false;
        }
      case 1:
        if (_locationCtrl.text.trim().isEmpty) {
          _snack('Please enter your location.');
          return false;
        }
        if (_emailCtrl.text.trim().isEmpty) {
          _snack('Please provide a contact email.');
          return false;
        }
        final age = int.tryParse(_ageCtrl.text.trim());
        if (age == null || age < 13 || age > 100) {
          _snack('Please enter a valid age (13–100).');
          return false;
        }
      case 2:
        break; // education is optional
      case 3:
        if (_selectedFieldIds.isEmpty) {
          _snack('Please choose at least one career field.');
          return false;
        }
      case 4:
        for (final id in _selectedFieldIds) {
          if (!_selectedSpecializations.containsKey(id) ||
              _selectedSpecializations[id]!.isEmpty) {
            final field = CareerFieldsData.getField(id);
            _snack('Please choose at least 1 specialization for ${field?['label'] ?? id}.');
            return false;
          }
        }
      case 6:
        break; // credentials optional
      case 7:
        break; // experience optional
    }
    return true;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit(color: kGoldLight)),
      backgroundColor: const Color(0xAA110E00),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    final svc = context.read<UserProfileService>();
    final fullName = '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}';

    // Build specializations as skills list
    final skills = _selectedSpecializations.values.expand((s) => s).toList();

    // Build education entry
    final List<Education> educations = [];
    if (_educationStatus != 'Prefer not to say' && _institutionCtrl.text.isNotEmpty) {
      educations.add(Education(
        id: const Uuid().v4(),
        degree: _degreeCtrl.text.trim().isNotEmpty
            ? _degreeCtrl.text.trim()
            : _educationStatus,
        institution: _institutionCtrl.text.trim(),
        fieldOfStudy: _fieldOfStudyCtrl.text.trim(),
        graduationYear: _gradYearCtrl.text.trim(),
      ));
    }

    // Build credentials as additional skills (simplified for now)
    final credentialSkills = _credentials.map((c) => c['title'] ?? '').where((s) => s.isNotEmpty).toList();

    svc.updateProfile(svc.profile.copyWith(
      name: fullName,
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text.trim()) ?? 0,
      careerFields: _selectedFieldIds
          .map((id) => CareerFieldsData.getField(id)?['label'] as String? ?? id)
          .toList(),
      skills: [...skills, ...credentialSkills],
      educations: educations,
      experiences: _experiences,
      bio: _bioCtrl.text.trim(),
    ));

    // Mark questionnaire as complete so it won't show again for this user
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('questionnaire_done_$uid', true);

    if (!mounted) return;
    // Auth gate StreamBuilder will handle navigation automatically
    // We just need to pop — _AuthGate will show MainShell
    Navigator.of(context).pushReplacementNamed('/main');
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
              Positioned(top: -80, right: -80,
                child: Container(width: 300, height: 300,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      kGold.withOpacity(0.08), Colors.transparent])))),
              Positioned(bottom: -60, left: -60,
                child: Container(width: 240, height: 240,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF2D1B5E).withOpacity(0.25), Colors.transparent])))),
            ]),
          ),
        ),

        SafeArea(
          child: Column(children: [
            // ── Header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(children: [
                Row(children: [
                  if (_step > 0)
                    GestureDetector(
                      onTap: _back,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: kGlassBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kGoldDim.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: kGold, size: 16),
                      ),
                    )
                  else
                    const SizedBox(width: 36),
                  const Spacer(),
                  Text('Step ${_step + 1} of $_totalSteps',
                      style: kLabel(12, color: kGoldDim)),
                ]),
                const SizedBox(height: 10),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _totalSteps,
                    minHeight: 4,
                    backgroundColor: kGoldDim.withOpacity(0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(kGold),
                  ),
                ),
              ]),
            ),

            // ── Pages ───────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepWrapper(child: _buildStep0()),
                  _StepWrapper(child: _buildStep1()),
                  _StepWrapper(child: _buildStep2()),
                  _StepWrapper(child: _buildStep3()),
                  _StepWrapper(child: _buildStep4()),
                  _StepWrapper(child: _buildStep5()),
                  _StepWrapper(child: _buildStep6()),
                  _StepWrapper(child: _buildStep7()),
                ],
              ),
            ),

            // ── CTA button ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: GestureDetector(
                onTap: _next,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: kGold.withOpacity(0.35), blurRadius: 20)],
                  ),
                  child: Center(child: Text(
                    _step == _totalSteps - 1 ? 'Complete Profile  ✦' : 'Continue  →',
                    style: GoogleFonts.outfit(color: kBg1, fontSize: 16, fontWeight: FontWeight.w800),
                  )),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 0: Name
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep0() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepTitle("What's your name?", "Let's start with the basics."),
      _glassField(_firstNameCtrl, 'First Name', Icons.person_outline),
      const SizedBox(height: 12),
      _glassField(_lastNameCtrl, 'Last Name', Icons.person_outline),
    ],
  );

  // ─────────────────────────────────────────────────────────────
  // STEP 1: Location & Contact
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepTitle('Where are you from?', 'Help us find local opportunities and contact you.'),
      _glassField(_locationCtrl, 'City, Country (e.g. Cairo, Egypt)', Icons.location_on_outlined),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _glassField(_ageCtrl, 'Age', Icons.cake_outlined,
            type: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: _glassField(_phoneCtrl, 'Phone (Optional)', Icons.phone_outlined, type: TextInputType.phone)),
      ]),
      const SizedBox(height: 12),
      _glassField(_emailCtrl, 'Contact Email', Icons.email_outlined, type: TextInputType.emailAddress),
    ],
  );

  // ─────────────────────────────────────────────────────────────
  // STEP 2: Education
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepTitle('What is your education level?', 'Select the option that best describes you.'),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: _eduStatuses.map((s) {
          final sel = _educationStatus == s;
          return GestureDetector(
            onTap: () => setState(() => _educationStatus = s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                gradient: sel ? kGoldGradient : null,
                color: sel ? null : kGlassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? kGold : kGoldDim.withOpacity(0.3)),
              ),
              child: Text(s, style: GoogleFonts.outfit(
                  color: sel ? kBg1 : kCream.withOpacity(0.7),
                  fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        }).toList(),
      ),
      if (_educationStatus.isNotEmpty && _educationStatus != 'High School' && _educationStatus != 'Prefer not to say') ...[
        const SizedBox(height: 18),
        _glassField(_institutionCtrl, 'Institution / University', Icons.school_outlined),
        const SizedBox(height: 10),
        _glassField(_degreeCtrl, 'Degree / Certificate Title', Icons.workspace_premium_outlined),
        const SizedBox(height: 10),
        _glassField(_fieldOfStudyCtrl, 'Field of Study', Icons.book_outlined),
        const SizedBox(height: 10),
        _glassField(_gradYearCtrl, 'Graduation Year (or expected)', Icons.calendar_today_outlined,
            type: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
      ],
    ],
  );

  // ─────────────────────────────────────────────────────────────
  // STEP 3: Career Fields
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepTitle('Which fields are you in?',
          'Choose up to 3 areas that describe your career.'),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: CareerFieldsData.fields.map((field) {
          final id  = field['id'] as String;
          final sel = _selectedFieldIds.contains(id);
          final canSelect = sel || _selectedFieldIds.length < 3;
          return GestureDetector(
            onTap: () {
              if (!canSelect) {
                _snack('Maximum 3 fields allowed.');
                return;
              }
              setState(() {
                if (sel) {
                  _selectedFieldIds.remove(id);
                  _selectedSpecializations.remove(id);
                } else {
                  _selectedFieldIds.add(id);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: sel ? kGoldGradient : null,
                color: sel ? null : kGlassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: sel ? kGold : (canSelect ? kGoldDim.withOpacity(0.3) : kGoldDim.withOpacity(0.1))),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(field['emoji'] as String, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(field['label'] as String, style: GoogleFonts.outfit(
                    color: sel ? kBg1 : (canSelect ? kCream.withOpacity(0.8) : kCream.withOpacity(0.3)),
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          );
        }).toList(),
      ),
      if (_selectedFieldIds.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Selected: ${_selectedFieldIds.length}/3',
            style: kLabel(12, color: kGoldDim)),
      ],
    ],
  );

  // ─────────────────────────────────────────────────────────────
  // STEP 4: Specializations
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep4() {
    final fieldList = _selectedFieldIds.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle('What are your specializations?',
            'Choose up to 3 specializations per field.'),
        ...fieldList.map((id) {
          final field = CareerFieldsData.getField(id);
          final specs = CareerFieldsData.getSpecializations(id);
          final chosen = _selectedSpecializations[id];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Row(children: [
                  Text(field?['emoji'] as String? ?? '', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(field?['label'] as String? ?? id,
                      style: kBody(14).copyWith(color: kGold, fontWeight: FontWeight.w700)),
                ]),
              ),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: specs.map((spec) {
                  final chosenSet = chosen ?? <String>{};
                  final sel = chosenSet.contains(spec);
                  final canSelect = sel || chosenSet.length < 3;
                  
                  return GestureDetector(
                    onTap: () {
                      if (!canSelect) {
                        _snack('Maximum 3 specializations per field.');
                        return;
                      }
                      setState(() {
                         final newSet = Set<String>.from(chosenSet);
                         if (sel) {
                           newSet.remove(spec);
                         } else {
                           newSet.add(spec);
                         }
                         _selectedSpecializations[id] = newSet;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: sel ? kGoldGradient : null,
                        color: sel ? null : kGlassBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: sel ? kGold : (canSelect ? kGoldDim.withOpacity(0.25) : kGoldDim.withOpacity(0.1))),
                      ),
                      child: Text(spec, style: GoogleFonts.outfit(
                          color: sel ? kBg1 : (canSelect ? kCream.withOpacity(0.7) : kCream.withOpacity(0.3)),
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 5: Bio
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep5() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stepTitle('Tell us about yourself', 'Write a short professional bio.'),
      _glassField(_bioCtrl, 'Your professional bio…', Icons.notes_rounded, maxLines: 6),
      const SizedBox(height: 10),
      Text('💡 Tip: mention your experience, what you love doing, and your goals.',
          style: kBody(12, opacity: 0.4)),
    ],
  );

  // ─────────────────────────────────────────────────────────────
  // STEP 6: Credentials
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep6() {
    final titleCtrl  = TextEditingController();
    final issuerCtrl = TextEditingController();
    final yearCtrl   = TextEditingController();
    return StatefulBuilder(builder: (ctx, setLocal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Credentials & Certificates', 'Add any internships or certifications you hold. (Optional)'),
          // Existing list
          ..._credentials.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: glassCard(borderRadius: 14),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: kGold, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.value['title'] ?? '', style: kBody(13).copyWith(fontWeight: FontWeight.w700)),
                Text('${e.value['issuer']} · ${e.value['year']}',
                    style: kBody(11, opacity: 0.5)),
              ])),
              GestureDetector(
                onTap: () => setState(() => _credentials.removeAt(e.key)),
                child: const Icon(Icons.close_rounded, color: kGoldDim, size: 16),
              ),
            ]),
          )),
          // Add new
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: glassCard(borderRadius: 16),
                child: Column(children: [
                  _miniField(titleCtrl,  'Certificate/Internship Title', Icons.card_membership_rounded),
                  const SizedBox(height: 8),
                  _miniField(issuerCtrl, 'Issuing Organization',         Icons.business_outlined),
                  const SizedBox(height: 8),
                  _miniField(yearCtrl,   'Year',                         Icons.calendar_today_outlined,
                      type: TextInputType.number),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      if (titleCtrl.text.trim().isEmpty) return;
                      setState(() {
                        _credentials.add({
                          'title':  titleCtrl.text.trim(),
                          'issuer': issuerCtrl.text.trim(),
                          'year':   yearCtrl.text.trim(),
                        });
                        titleCtrl.clear();
                        issuerCtrl.clear();
                        yearCtrl.clear();
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: kGoldDim.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(12),
                        color: kGlassBg,
                      ),
                      child: Center(child: Text('+ Add Credential',
                          style: kLabel(13, color: kGold))),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ─────────────────────────────────────────────────────────────
  // STEP 7: Past Experience
  // ─────────────────────────────────────────────────────────────
  Widget _buildStep7() {
    final titleCtrl   = TextEditingController();
    final companyCtrl = TextEditingController();
    final startCtrl   = TextEditingController();
    final endCtrl     = TextEditingController();
    final descCtrl    = TextEditingController();
    return StatefulBuilder(builder: (ctx, setLocal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Work Experience', 'Add your past jobs or internships. (Optional)'),
          ..._experiences.asMap().entries.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: glassCard(borderRadius: 14),
            child: Row(children: [
              const Icon(Icons.work_outline_rounded, color: kGold, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.value.jobTitle, style: kBody(13).copyWith(fontWeight: FontWeight.w700)),
                Text('${e.value.company} · ${e.value.startDate} – ${e.value.endDate}',
                    style: kBody(11, opacity: 0.5)),
              ])),
              GestureDetector(
                onTap: () => setState(() => _experiences.removeAt(e.key)),
                child: const Icon(Icons.close_rounded, color: kGoldDim, size: 16),
              ),
            ]),
          )),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: glassCard(borderRadius: 16),
                child: Column(children: [
                  _miniField(titleCtrl,   'Job Title',       Icons.badge_outlined),
                  const SizedBox(height: 8),
                  _miniField(companyCtrl, 'Company / Place', Icons.business_outlined),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _miniField(startCtrl, 'Start (e.g. Jan 2022)', Icons.play_arrow_rounded)),
                    const SizedBox(width: 8),
                    Expanded(child: _miniField(endCtrl, 'End / Present', Icons.stop_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  _miniField(descCtrl, 'Short description', Icons.notes_rounded, maxLines: 2),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      if (titleCtrl.text.trim().isEmpty || companyCtrl.text.trim().isEmpty) return;
                      setState(() {
                        _experiences.add(Experience(
                          id: const Uuid().v4(),
                          jobTitle: titleCtrl.text.trim(),
                          company:  companyCtrl.text.trim(),
                          startDate: startCtrl.text.trim(),
                          endDate:  endCtrl.text.trim().isEmpty ? 'Present' : endCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                        ));
                        titleCtrl.clear(); companyCtrl.clear();
                        startCtrl.clear(); endCtrl.clear(); descCtrl.clear();
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: kGoldDim.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(12),
                        color: kGlassBg,
                      ),
                      child: Center(child: Text('+ Add Experience',
                          style: kLabel(13, color: kGold))),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────

  Widget _stepTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: kHeadline(26))
          .animate().fadeIn(duration: 400.ms).slideY(begin: -0.08),
      const SizedBox(height: 6),
      Text(subtitle, style: kBody(14, opacity: 0.5))
          .animate().fadeIn(duration: 400.ms, delay: 100.ms),
      const SizedBox(height: 22),
    ],
  );

  Widget _glassField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      style: kBody(14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: kBody(13, opacity: 0.3),
        prefixIcon: maxLines == 1
            ? Icon(icon, color: kGoldDim, size: 18)
            : Padding(padding: const EdgeInsets.all(12),
                child: Icon(icon, color: kGoldDim, size: 18)),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        filled: true,
        fillColor: kGlassBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kGold, width: 1.5)),
      ),
    );
  }

  Widget _miniField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      style: kBody(13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: kBody(12, opacity: 0.3),
        prefixIcon: Icon(icon, color: kGoldDim, size: 16),
        filled: true,
        fillColor: kBg1.withOpacity(0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kGoldDim.withOpacity(0.15))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kGold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper: wraps each step page with scroll + padding
// ─────────────────────────────────────────────────────────────
class _StepWrapper extends StatelessWidget {
  final Widget child;
  const _StepWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: child,
    );
  }
}
