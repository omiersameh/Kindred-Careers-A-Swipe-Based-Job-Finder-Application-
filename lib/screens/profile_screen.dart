import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';
import '../services/auth_service.dart';

// ============================================================
// SCREEN: ProfileScreen — Kindred Careers Style
// Gold + glassmorphism aesthetic with profile completion bar,
// skill pills with gold borders, experience & education list
// ============================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _bioCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _skillCtrl;
  late TextEditingController _careerFieldCtrl;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<UserProfileService>().profile;
    _nameCtrl = TextEditingController(text: p.name);
    _emailCtrl = TextEditingController(text: p.email);
    _phoneCtrl = TextEditingController(text: p.phone);
    _bioCtrl = TextEditingController(text: p.bio);
    _locationCtrl = TextEditingController(text: p.location);
    _skillCtrl = TextEditingController();
    _careerFieldCtrl = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _bioCtrl,
      _locationCtrl,
      _skillCtrl,
      _careerFieldCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _profileCompletion(UserProfile p) {
    int filled = 0;
    if (p.name.isNotEmpty) filled++;
    if (p.email.isNotEmpty) filled++;
    if (p.bio.isNotEmpty) filled++;
    if (p.location.isNotEmpty) filled++;
    if (p.skills.isNotEmpty) filled++;
    if (p.careerFields.isNotEmpty) filled++;
    if (p.experiences.isNotEmpty) filled++;
    if (p.educations.isNotEmpty) filled++;
    return filled / 8;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 400));
    final svc = context.read<UserProfileService>();
    svc.updateProfile(svc.profile.copyWith(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
    ));
    setState(() {
      _isSaving = false;
      _isEditing = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✦ Profile saved',
            style: GoogleFonts.outfit(color: kGoldLight)),
        backgroundColor: const Color(0xAA1A1200),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Consumer<UserProfileService>(
          builder: (context, svc, _) {
            final profile = svc.profile;
            final completion = _profileCompletion(profile);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  // ── Header
                  _buildHeaderRow(profile),
                  const SizedBox(height: 24),

                  // ── Avatar card
                  _buildProfileCard(profile, completion),
                  const SizedBox(height: 20),

                  // ── Bio
                  _glassSection('BIO', [
                    _isEditing
                        ? _goldField(_bioCtrl, 'Professional bio…', maxLines: 4)
                        : Text(
                            profile.bio.isNotEmpty
                                ? profile.bio
                                : 'Tap ✏️ to add your professional bio',
                            style: kBody(14,
                                opacity: profile.bio.isNotEmpty ? 0.8 : 0.4)),
                  ]),
                  const SizedBox(height: 16),

                  // ── Fields (edit mode)
                  if (_isEditing) ...[
                    _glassSection('BASIC INFO', [
                      _goldField(_nameCtrl, 'Full Name',
                          icon: Icons.person_outline),
                      _goldField(_emailCtrl, 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          required: true),
                      _goldField(_phoneCtrl, 'Phone',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone),
                      _goldField(_locationCtrl, 'Location',
                          icon: Icons.location_on_outlined),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // ── Career Fields
                  _glassSection('CAREER FIELDS', [
                    _pillChips(profile.careerFields,
                        onRemove: _isEditing ? svc.removeCareerField : null),
                    if (_isEditing)
                      _addPillRow(_careerFieldCtrl, 'Add field…', () {
                        svc.addCareerField(_careerFieldCtrl.text);
                        _careerFieldCtrl.clear();
                      }),
                  ]),
                  const SizedBox(height: 16),

                  // ── Skills
                  _glassSection('CREDENTIALS & SKILLS', [
                    _pillChips(profile.skills,
                        onRemove: _isEditing ? svc.removeSkill : null),
                    if (_isEditing)
                      _addPillRow(
                          _skillCtrl, 'Add skill (e.g. Flutter, Python)…', () {
                        svc.addSkill(_skillCtrl.text);
                        _skillCtrl.clear();
                      }),
                  ]),
                  const SizedBox(height: 16),

                  // ── Work Mode
                  _glassSection('PREFERRED WORK MODE', [
                    Wrap(
                      spacing: 10,
                      children: ['Remote', 'Hybrid', 'On-site'].map((mode) {
                        final sel = profile.preferredWorkMode == mode;
                        return GestureDetector(
                          onTap: _isEditing
                              ? () => svc.updateProfile(
                                  profile.copyWith(preferredWorkMode: mode))
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: sel ? kGoldGradient : null,
                              color: sel ? null : kGlassBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel ? kGold : kGoldDim.withOpacity(0.3),
                              ),
                            ),
                            child: Text(mode,
                                style: GoogleFonts.outfit(
                                    color: sel ? kBg1 : kCream.withOpacity(0.6),
                                    fontSize: 13,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w400)),
                          ),
                        );
                      }).toList(),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  // ── Experience
                  _glassSection('EXPERIENCE', [
                    if (profile.experiences.isEmpty)
                      Text('No experience added yet',
                          style: kBody(13, opacity: 0.4))
                    else
                      ...profile.experiences.map((e) => _experienceRow(e, svc)),
                    if (_isEditing)
                      _outlineBtn('+ Add Experience',
                          () => _showAddExperienceDialog(svc)),
                  ]),
                  const SizedBox(height: 16),

                  // ── Education
                  _glassSection('EDUCATION', [
                    if (profile.educations.isEmpty)
                      Text('No education added yet',
                          style: kBody(13, opacity: 0.4))
                    else
                      ...profile.educations.map((e) => _educationRow(e, svc)),
                  ]),

                  // ── Save button
                  if (_isEditing) ...[
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _isSaving ? null : _saveProfile,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: kGoldGradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: kGold.withOpacity(0.35), blurRadius: 20)
                          ],
                        ),
                        child: Center(
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kBg1))
                              : Text('Save Profile',
                                  style: GoogleFonts.outfit(
                                      color: kBg1,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Header Row ───────────────────────────────────────────
  Widget _buildHeaderRow(UserProfile profile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Kindred Careers', style: kHeadline(22)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                await AuthService.signOut();
                if (context.mounted) {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: const Color(0xFFFF5252).withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(20),
                  color: kGlassBg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded,
                        color: Color(0xFFFF5252), size: 14),
                    const SizedBox(width: 5),
                    Text('Logout',
                        style: GoogleFonts.outfit(
                            color: const Color(0xFFFF5252),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isEditing = !_isEditing),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: kGoldDim.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(20),
                  color: kGlassBg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isEditing ? Icons.close_rounded : Icons.edit_outlined,
                        color: kGold, size: 14),
                    const SizedBox(width: 5),
                    Text(_isEditing ? 'Cancel' : 'Edit',
                        style: GoogleFonts.outfit(
                            color: kGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Profile Card (avatar + name + progress) ──────────────
  Widget _buildProfileCard(UserProfile profile, double completion) {
    final initials = profile.name.isNotEmpty
        ? profile.name
            .trim()
            .split(' ')
            .map((w) => w[0].toUpperCase())
            .take(2)
            .join()
        : '?';
    final pct = (completion * 100).toInt();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: glassCard(borderRadius: 22),
          child: Column(children: [
            // Avatar
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: kGoldGradient,
                boxShadow: [
                  BoxShadow(color: kGold.withOpacity(0.4), blurRadius: 20)
                ],
              ),
              child: Center(
                child: Text(initials,
                    style: GoogleFonts.outfit(
                        color: kBg1,
                        fontSize: 30,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),

            Text(profile.name.isNotEmpty ? profile.name : 'Your Name',
                style: kHeadline(20)),
            const SizedBox(height: 4),
            Text(
                profile.careerFields.isNotEmpty
                    ? profile.careerFields.first
                    : 'Add your career field',
                style: kBody(13, opacity: 0.6)),
            if (profile.location.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined, size: 12, color: kGoldDim),
                const SizedBox(width: 4),
                Text(profile.location,
                    style: kBody(12, color: kGoldDim, opacity: 0.8)),
              ]),
            ],

            const SizedBox(height: 18),
            // Profile completion bar
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Profile complete',
                              style: kLabel(10, color: kGoldDim)),
                          Text('$pct%', style: kLabel(11)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: completion,
                          backgroundColor: kGoldDim.withOpacity(0.2),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(kGold),
                          minHeight: 5,
                        ),
                      ),
                    ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ─── Section Container ────────────────────────────────────
  Widget _glassSection(String title, List<Widget> children) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: glassCard(borderRadius: 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(title, style: kLabel(10)),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: kGoldDim.withOpacity(0.2))),
            ]),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      ),
    );
  }

  // ─── Gold-bordered text field ─────────────────────────────
  Widget _goldField(
    TextEditingController ctrl,
    String hint, {
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: kBody(14),
        validator: required
            ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null
            : null,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: kBody(13, opacity: 0.35),
          prefixIcon:
              icon != null ? Icon(icon, color: kGoldDim, size: 18) : null,
          filled: true,
          fillColor: kGlassBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kGoldDim.withOpacity(0.4))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kGoldDim.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGold, width: 1.5)),
        ),
      ),
    );
  }

  // ─── Gold pill chips ─────────────────────────────────────
  Widget _pillChips(List<String> chips, {void Function(String)? onRemove}) {
    if (chips.isEmpty) {
      return Text('None added yet', style: kBody(13, opacity: 0.4));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map((c) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kGold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kGoldDim.withOpacity(0.5)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(c,
                      style: GoogleFonts.outfit(
                          color: kGoldLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  if (onRemove != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onRemove(c),
                      child: const Icon(Icons.close, size: 13, color: kGoldDim),
                    ),
                  ],
                ]),
              ))
          .toList(),
    );
  }

  Widget _addPillRow(
      TextEditingController ctrl, String hint, VoidCallback onAdd) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            style: kBody(13),
            onSubmitted: (_) => onAdd(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: kBody(12, opacity: 0.3),
              filled: true,
              fillColor: kGlassBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kGoldDim.withOpacity(0.3))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kGoldDim.withOpacity(0.25))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kGold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add, color: kBg1, size: 18),
          ),
        ),
      ]),
    );
  }

  Widget _experienceRow(Experience exp, UserProfileService svc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: goldBorderCard(),
      child: Row(children: [
        const Text('💼', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exp.jobTitle, style: kBody(14, color: kCream)),
          Text('${exp.company}  ·  ${exp.startDate} – ${exp.endDate}',
              style: kBody(12, color: kGoldDim)),
        ])),
        if (_isEditing)
          GestureDetector(
            onTap: () => svc.removeExperience(exp.id),
            child: const Icon(Icons.close, color: Color(0xFFFF5252), size: 16),
          ),
      ]),
    );
  }

  Widget _educationRow(Education edu, UserProfileService svc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: goldBorderCard(),
      child: Row(children: [
        const Text('🎓', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(edu.degree, style: kBody(14, color: kCream)),
          Text('${edu.fieldOfStudy} — ${edu.institution}',
              style: kBody(12, color: kGoldDim)),
          Text('Graduated: ${edu.graduationYear}',
              style: kBody(11, color: kGoldDim, opacity: 0.7)),
        ])),
        if (_isEditing)
          GestureDetector(
            onTap: () => svc.removeEducation(edu.id),
            child: const Icon(Icons.close, color: Color(0xFFFF5252), size: 16),
          ),
      ]),
    );
  }

  Widget _outlineBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kGoldDim.withOpacity(0.4)),
        ),
        child: Center(child: Text(label, style: kLabel(12))),
      ),
    );
  }

  void _showAddExperienceDialog(UserProfileService svc) {
    final titleCtrl = TextEditingController();
    final companyCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController(text: 'Present');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: kGoldDim.withOpacity(0.4))),
        title: Text('Add Experience', style: kHeadline(18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final pair in [
            (titleCtrl, 'Job Title'),
            (companyCtrl, 'Company'),
            (startCtrl, 'Start Date (e.g. Jan 2022)'),
            (endCtrl, 'End Date'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: pair.$1,
                style: kBody(13),
                decoration: InputDecoration(
                  hintText: pair.$2,
                  hintStyle: kBody(12, opacity: 0.35),
                  filled: true,
                  fillColor: kGlassBg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: kGoldDim.withOpacity(0.3))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: kGoldDim.withOpacity(0.25))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kGold)),
                ),
              ),
            ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: kBody(14, color: kGoldDim)),
          ),
          GestureDetector(
            onTap: () {
              if (titleCtrl.text.isNotEmpty && companyCtrl.text.isNotEmpty) {
                svc.addExperience(Experience(
                  id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
                  jobTitle: titleCtrl.text,
                  company: companyCtrl.text,
                  startDate: startCtrl.text,
                  endDate: endCtrl.text,
                ));
                Navigator.pop(ctx);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: kGoldGradient,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('Add',
                  style: GoogleFonts.outfit(
                      color: kBg1, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
