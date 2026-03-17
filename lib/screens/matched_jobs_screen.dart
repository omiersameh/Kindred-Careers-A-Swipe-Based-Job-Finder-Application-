import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../models/job.dart';
import '../services/cv_generation_service.dart';
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
            'Swipe right on jobs you like to generate tailored CVs and apply',
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
// ============================================================

class _MatchCard extends StatelessWidget {
  final Job job;
  final dynamic cv;
  final AppState appState;

  const _MatchCard(
      {required this.job, required this.cv, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              border: Border.all(color: kGoldDim.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      child: Text(job.logoEmoji,
                          style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.title,
                            style: GoogleFonts.outfit(
                                color: kCream,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(job.company,
                            style: kBody(13, color: kGoldDim, opacity: 0.85)),
                      ]),
                ),
                // Match badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(job.matchPercent,
                      style: GoogleFonts.outfit(
                          color: kBg1,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ]),

              const SizedBox(height: 12),
              // ── Meta chips
              Wrap(spacing: 8, runSpacing: 6, children: [
                _chip(Icons.location_on_outlined, job.location),
                _chip(Icons.laptop_mac_outlined, job.workMode),
                if (job.salaryRange.isNotEmpty)
                  _chip(Icons.monetization_on_outlined, job.salaryRange),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                // View CV
                if (cv != null)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _viewCV(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: kGold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kGoldDim.withOpacity(0.4)),
                        ),
                        child: Center(
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.description_outlined,
                              color: kGold, size: 14),
                          const SizedBox(width: 6),
                          Text('View CV', style: kLabel(12)),
                        ])),
                      ),
                    ),
                  ),
                if (cv != null) const SizedBox(width: 8),
                // Apply
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
                              color: kGold.withOpacity(0.25), blurRadius: 10)
                        ],
                      ),
                      child: Center(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.send_rounded, color: kBg1, size: 14),
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
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cvStatus() {
    if (cv == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kGlassBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGoldDim.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_empty_rounded, color: kGoldDim, size: 13),
          const SizedBox(width: 6),
          Text('Awaiting CV Generation', style: kBody(11, color: kGoldDim)),
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
          cv.wasModified
              ? 'CV Tailored (v${cv.regenerationCount + 1})'
              : 'CV Tailored ✓',
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
        Text(label, style: kBody(11, color: kGoldDim, opacity: 0.8)),
      ]),
    );
  }

  void _viewCV(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          CVPreviewDialog(job: job, initialCV: cv!, isNewMatch: false),
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
        title: Text('Apply to ${job.title}?', style: kHeadline(17)),
        content: Text(
          'Your tailored CV will be submitted to ${job.company}.',
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
                content: Text('✦ Applied to ${job.company}!',
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
        content: Text('This will remove ${job.title} from your saved matches.',
            style: kBody(14, opacity: 0.7)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: kBody(14, color: kGoldDim)),
          ),
          TextButton(
            onPressed: () {
              appState.removeMatch(job.id);
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
