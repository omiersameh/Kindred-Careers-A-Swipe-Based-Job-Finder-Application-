import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/job.dart';
import '../services/cv_generation_service.dart';
import '../services/user_profile_service.dart';
import '../widgets/cv_preview_dialog.dart';

// ============================================================
// SCREEN: MatchedJobsScreen — Matches (Saved Jobs & CVs)
// Gold glassmorphism match cards with status badges and actions
// ============================================================

class MatchedJobsScreen extends StatelessWidget {
  const MatchedJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Matches', style: kHeadline(26)),
                Consumer<AppState>(
                  builder: (_, state, __) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient:
                          state.matchedJobs.isNotEmpty ? kGoldGradient : null,
                      color: state.matchedJobs.isEmpty ? kGlassBg : null,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kGoldDim.withOpacity(0.5)),
                    ),
                    child: Text(
                      '${state.matchedJobs.length} saved',
                      style: GoogleFonts.outfit(
                        color: state.matchedJobs.isNotEmpty ? kBg1 : kGoldDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Text('YOUR SAVED MATCHES', style: kLabel(10, color: kGoldDim)),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: kGoldDim.withOpacity(0.2))),
            ]),
          ),

          // ── List
          Expanded(
            child: Consumer<AppState>(
              builder: (context, appState, _) {
                if (appState.isLoadingMatches) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGoldDim),
                  );
                }
                if (appState.matchedJobs.isEmpty) return _buildEmpty();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: appState.matchedJobs.length,
                  itemBuilder: (context, index) {
                    final job = appState.matchedJobs[index];
                    final cv = appState.getCVForJob(job.id);
                    return _MatchCard(job: job, cv: cv, appState: appState);
                  },
                );
              },
            ),

          ),
        ]),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('✦', style: TextStyle(fontSize: 52, color: kGold)),
        const SizedBox(height: 16),
        Text('No matches yet', style: kHeadline(22)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Swipe right on jobs you like — they\'ll appear here instantly while your CV is being crafted',
            style: kBody(14, opacity: 0.5),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

// ============================================================
// WIDGET: _MatchCard — individual glassmorphism match card
// Tappable: opens CV preview sheet
// ============================================================

class _MatchCard extends StatefulWidget {
  final Job job;
  final dynamic cv;
  final AppState appState;

  const _MatchCard(
      {required this.job, required this.cv, required this.appState});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _isGeneratingCV = false;
  bool _isDownloadingPDF = false;

  void _openCVPreview() {
    if (widget.cv == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CVPreviewDialog(
        job: widget.job,
        initialCV: widget.cv!,
        isNewMatch: false,
      ),
    );
  }

  Future<void> _generateCV() async {
    setState(() => _isGeneratingCV = true);
    try {
      final profile = context.read<UserProfileService>().profile;
      final cvService = CVGenerationService();
      final cv = await cvService.generateCV(job: widget.job, profile: profile);
      if (mounted) {
        widget.appState.updateCV(widget.job.id, cv);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF4CAF50), size: 16),
            const SizedBox(width: 8),
            Text('CV generated! Tap to preview.',
                style: GoogleFonts.outfit(color: Colors.white)),
          ]),
          backgroundColor: const Color(0xFF1B3A2B),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CV generation failed. Try again.',
              style: GoogleFonts.outfit(color: Colors.white)),
          backgroundColor: const Color(0xAAD32F2F),
        ));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingCV = false);
    }
  }

  Future<void> _downloadPDF() async {
    if (widget.cv == null) return;
    setState(() => _isDownloadingPDF = true);
    try {
      final profile = context.read<UserProfileService>().profile;
      final cvService = CVGenerationService();
      final path = await cvService.downloadCVPdf(
        cv: widget.cv!,
        profile: profile,
        job: widget.job,
      );
      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.picture_as_pdf, color: kGold, size: 16),
              const SizedBox(width: 8),
              const Expanded(child: Text('PDF saved & opened!')),
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
      if (mounted) setState(() => _isDownloadingPDF = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.cv != null ? _openCVPreview : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kGlassBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.cv != null
                      ? kGoldDim.withOpacity(0.4)
                      : kGoldDim.withOpacity(0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // ── Header
                Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kGold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kGoldDim.withOpacity(0.4)),
                    ),
                    child: Center(
                        child: Text(widget.job.logoEmoji,
                            style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.job.title,
                              style: GoogleFonts.outfit(
                                  color: kCream,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text(widget.job.company,
                              style:
                                  kBody(13, color: kGoldDim, opacity: 0.85)),
                        ]),
                  ),
                  // Match badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: kGoldGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(widget.job.matchPercent,
                        style: GoogleFonts.outfit(
                            color: kBg1,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),

                const SizedBox(height: 12),
                // ── Meta chips
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _chip(Icons.location_on_outlined, widget.job.location),
                  _chip(Icons.laptop_mac_outlined, widget.job.workMode),
                  if (widget.job.salaryRange.isNotEmpty)
                    _chip(Icons.monetization_on_outlined,
                        widget.job.salaryRange),
                ]),

                const SizedBox(height: 12),
                // ── CV status
                _cvStatus(),
                const SizedBox(height: 14),

                // ── Actions
                Row(children: [
                  // Remove
                  GestureDetector(
                    onTap: () => _confirmRemove(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFFF5252).withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Color(0xFFFF5252), size: 16),
                    ),
                  ),
                  const SizedBox(width: 8),

                  if (widget.cv == null) ...[
                    // Generate CV button
                    Expanded(
                      child: GestureDetector(
                        onTap: _isGeneratingCV ? null : _generateCV,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: kGoldGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: kGold.withOpacity(0.25),
                                  blurRadius: 10),
                            ],
                          ),
                          child: Center(
                            child: _isGeneratingCV
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: kBg1))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.auto_awesome_rounded,
                                          color: kBg1, size: 14),
                                      const SizedBox(width: 6),
                                      Text('Generate CV',
                                          style: GoogleFonts.outfit(
                                              color: kBg1,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Download PDF button
                    GestureDetector(
                      onTap: _isDownloadingPDF ? null : _downloadPDF,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: kGoldDim.withOpacity(0.5)),
                          color: kGold.withOpacity(0.06),
                        ),
                        child: _isDownloadingPDF
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kGold))
                            : const Icon(Icons.picture_as_pdf_outlined,
                                color: kGold, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Preview CV button
                    Expanded(
                      child: GestureDetector(
                        onTap: _openCVPreview,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: kGold.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: kGoldDim.withOpacity(0.4)),
                          ),
                          child: Center(
                              child:
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.description_outlined,
                                color: kGold, size: 14),
                            const SizedBox(width: 6),
                            Text('Preview CV', style: kLabel(12)),
                          ])),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Apply button
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showApplyConfirmation(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: kGoldGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: kGold.withOpacity(0.25),
                                  blurRadius: 10)
                            ],
                          ),
                          child: Center(
                              child:
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.send_rounded,
                                color: kBg1, size: 14),
                            const SizedBox(width: 6),
                            Text('Apply',
                                style: GoogleFonts.outfit(
                                    color: kBg1,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ])),
                        ),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cvStatus() {
    if (widget.cv == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kGlassBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGoldDim.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: kGoldDim),
          ),
          const SizedBox(width: 8),
          Text('Generating CV…', style: kBody(11, color: kGoldDim)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: Color(0xFF4CAF50), size: 13),
        const SizedBox(width: 6),
        Text(
          widget.cv.wasModified
              ? 'CV Tailored (v${widget.cv.regenerationCount + 1}) · Tap to preview'
              : 'CV Ready · Tap card to preview',
          style:
              GoogleFonts.outfit(color: const Color(0xFF4CAF50), fontSize: 12),
        ),
      ]),
    );
  }

  Widget _chip(IconData icon, String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: kGlassBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGoldDim.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: kGoldDim.withOpacity(0.7)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: kBody(11, color: kGoldDim, opacity: 0.8),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  void _showApplyConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: kGoldDim.withOpacity(0.4))),
        title: Text('Apply to ${widget.job.title}?', style: kHeadline(17)),
        content: Text(
          'Your tailored CV will be submitted to ${widget.job.company}.',
          style: kBody(14, opacity: 0.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: kBody(14, color: kGoldDim)),
          ),
          GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('✦ Applied to ${widget.job.company}!',
                    style: GoogleFonts.outfit(color: kGoldLight)),
                backgroundColor: const Color(0xAA1A1200),
              ));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: kGoldGradient,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('Confirm Apply',
                  style: GoogleFonts.outfit(
                      color: kBg1, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: kGoldDim.withOpacity(0.4))),
        title: Text('Remove Match?', style: kHeadline(17)),
        content: Text(
            'This will remove ${widget.job.title} from your saved matches.',
            style: kBody(14, opacity: 0.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: kBody(14, color: kGoldDim)),
          ),
          TextButton(
            onPressed: () {
              widget.appState.removeMatch(widget.job.id);
              Navigator.pop(ctx);
            },
            child: Text('Remove',
                style: GoogleFonts.outfit(
                    color: const Color(0xFFFF5252),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
