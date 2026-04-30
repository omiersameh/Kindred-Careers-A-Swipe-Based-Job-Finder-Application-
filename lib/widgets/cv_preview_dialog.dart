import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/cv.dart';
import '../models/job.dart';
import '../services/cv_generation_service.dart';
import '../services/user_profile_service.dart';
import '../app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ============================================================
// WIDGET: CVPreviewDialog
// Full-screen bottom sheet showing the generated CV.
// Includes feedback input and regeneration loop.
// ============================================================

class CVPreviewDialog extends StatefulWidget {
  final Job job;
  final CV initialCV;
  final bool isNewMatch; // true = show "Confirm & Apply" button

  const CVPreviewDialog({
    super.key,
    required this.job,
    required this.initialCV,
    this.isNewMatch = true,
  });

  @override
  State<CVPreviewDialog> createState() => _CVPreviewDialogState();
}

class _CVPreviewDialogState extends State<CVPreviewDialog> {
  late CV _currentCV;
  bool _isRegenerating = false;
  bool _isDownloadingPdf = false;
  bool _showFeedbackInput = false;
  final _feedbackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentCV = widget.initialCV;
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _regenerate() async {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) return;

    setState(() => _isRegenerating = true);

    final cvService = CVGenerationService();
    final profile = context.read<UserProfileService>().profile;
    final fb = CVFeedback(
      id: 'fb_${DateTime.now().millisecondsSinceEpoch}',
      feedbackText: feedback,
    );

    final updated = await cvService.regenerateWithFeedback(
      existingCV: _currentCV,
      feedback: fb,
      job: widget.job,
      profile: profile,
    );

    // Update in global state
    if (mounted) {
      context.read<AppState>().updateCV(widget.job.id, updated);
      setState(() {
        _currentCV = updated;
        _isRegenerating = false;
        _showFeedbackInput = false;
        _feedbackController.clear();
      });
    }
  }

  void _confirmApply() {
    final appState = context.read<AppState>();
    appState.addMatch(widget.job, _currentCV);
    Navigator.of(context).pop(true); // true = confirmed match
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Applied to ${widget.job.title} at ${widget.job.company}!',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _downloadPdf() async {
    setState(() => _isDownloadingPdf = true);
    try {
      final profile = context.read<UserProfileService>().profile;
      final cvService = CVGenerationService();
      final path = await cvService.downloadCVPdf(
        cv: _currentCV,
        profile: profile,
        job: widget.job,
      );
      if (mounted) {
        if (path != null) {
          _currentCV.localPdfPath = path;
          context.read<AppState>().updateCV(widget.job.id, _currentCV);
          
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.picture_as_pdf, color: kGold, size: 16),
              const SizedBox(width: 8),
              const Expanded(child: Text('PDF saved and opened!')),
            ]),
            backgroundColor: const Color(0xFF1A1200),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('PDF download failed. Is the backend running?'),
            backgroundColor: Color(0xAAD32F2F),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _isDownloadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: kBg1.withOpacity(0.9),
                border: Border(top: BorderSide(color: kGoldDim.withOpacity(0.3))),
              ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              _buildHeader(),
              // Scrollable CV content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: _isRegenerating
                      ? _buildLoadingState()
                      : _buildCVContent(),
                ),
              ),
              // Feedback + Action buttons
              _buildActionBar(),
            ],
          ),
        ),
        ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Text(widget.job.logoEmoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Tailored CV',
                  style: kHeadline(18),
                ),
                Text(
                  '${widget.job.title} · ${widget.job.company}',
                  style: kBody(13, opacity: 0.6),
                ),
              ],
            ),
          ),
          if (_currentCV.wasModified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'v${_currentCV.regenerationCount + 1}',
                style: GoogleFonts.inter(color: Colors.orange, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCVContent() {
    final cv = _currentCV.content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('👤 Professional Summary', cv.summary).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
        const SizedBox(height: 20),
        _section('⚡ Key Skills', null, chips: cv.highlightedSkills).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideX(begin: -0.1),
        const SizedBox(height: 20),
        _sectionTitle('💼 Relevant Experience').animate().fadeIn(duration: 400.ms, delay: 200.ms),
        ...cv.relevantExperiences.asMap().entries.map((e) => _expCard(e.value).animate().fadeIn(duration: 400.ms, delay: (250 + (e.key * 100)).ms).slideX(begin: -0.1)),
        const SizedBox(height: 20),
        _section('🎓 Education', cv.educationEntries.join('\n')).animate().fadeIn(duration: 400.ms, delay: 400.ms).slideX(begin: -0.1),
        const SizedBox(height: 20),
        _section(
          '🏆 Key Achievements',
          cv.keyAchievements.map((a) => '• $a').join('\n'),
        ).animate().fadeIn(duration: 400.ms, delay: 500.ms).slideX(begin: -0.1),
      ],
    );
  }

  Widget _section(String title, String? text, {List<String>? chips}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        const SizedBox(height: 8),
        if (text != null)
          Text(
            text,
            style: kBody(14, opacity: 0.8).copyWith(height: 1.6),
          ),
        if (chips != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: chips
                .map(
                  (s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: kGlassBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kGoldDim.withOpacity(0.3)),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: kCream,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _expCard(CVExperience exp) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: glassCard(borderRadius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exp.jobTitle,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Text(
            '${exp.company}  ·  ${exp.duration}',
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...exp.tailoredBullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Color(0xFF4A90E2))),
                  Expanded(
                    child: Text(
                      b,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: kGold, strokeWidth: 2),
            const SizedBox(height: 20),
            Text(
              '✦ AI is tailoring your CV…',
              style: kBody(14, opacity: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: kBg1.withOpacity(0.9),
            border: Border(top: BorderSide(color: kGoldDim.withOpacity(0.2))),
          ),
      child: Column(
        children: [
          if (_showFeedbackInput) ...[
            TextField(
              controller: _feedbackController,
              style: GoogleFonts.inter(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. "Focus more on my Python and ML skills"',
                hintStyle: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4A90E2)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _showFeedbackInput = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Cancel', style: GoogleFonts.inter()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isRegenerating ? null : _regenerate,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: Text(
                      'Regenerate CV',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF533483),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showFeedbackInput = !_showFeedbackInput),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text('Request Changes', style: GoogleFonts.inter()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.25)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Download PDF button
              GestureDetector(
                onTap: _isDownloadingPdf ? null : _downloadPdf,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: kGold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGoldDim.withOpacity(0.4)),
                  ),
                  child: _isDownloadingPdf
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kGold))
                      : const Icon(Icons.picture_as_pdf_outlined,
                          color: kGold, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
        ),
      ),
    );
  }
}
