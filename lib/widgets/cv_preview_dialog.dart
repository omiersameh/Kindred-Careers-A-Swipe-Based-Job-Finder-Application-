import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/cv.dart';
import '../models/job.dart';
import '../services/cv_generation_service.dart';
import '../services/user_profile_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D1B2A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.job.title} · ${widget.job.company}',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
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
        _section('👤 Professional Summary', cv.summary),
        const SizedBox(height: 20),
        _section('⚡ Key Skills', null, chips: cv.highlightedSkills),
        const SizedBox(height: 20),
        _sectionTitle('💼 Relevant Experience'),
        ...cv.relevantExperiences.map((e) => _expCard(e)),
        const SizedBox(height: 20),
        _section('🎓 Education', cv.educationEntries.join('\n')),
        const SizedBox(height: 20),
        _section(
          '🏆 Key Achievements',
          cv.keyAchievements.map((a) => '• $a').join('\n'),
        ),
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
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        if (chips != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: chips
                .map(
                  (s) => Chip(
                    label: Text(
                      s,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: const Color(0xFF1A3A5C),
                    side: const BorderSide(color: Color(0xFF2A5F8A)),
                    padding: EdgeInsets.zero,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
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
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 300,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4A90E2)),
            SizedBox(height: 20),
            Text(
              '🤖 LLM is tailoring your CV…',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
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
              if (widget.isNewMatch)
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _confirmApply,
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      'Apply Now',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
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
        ],
      ),
    );
  }
}
