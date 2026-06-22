import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';
import '../models/job.dart';
import '../utils/banner_selector.dart';

// ============================================================
// WIDGET: JobCard — Premium glass-morphism swipe card
// Bumble/Tinder aesthetic with gold accents + dark gradient
// Fully scrollable: hero → AI bullets → description → skills
// ============================================================

class JobCard extends StatefulWidget {
  final Job job;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final ValueNotifier<double>? scrollNotifier;

  const JobCard({
    super.key,
    required this.job,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.scrollNotifier,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  final ScrollController _scroll = ScrollController();
  bool _atBottom = false;
  String? _localBanner;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _localBanner = BannerSelector.getRandomBanner(
        widget.job.careerField, widget.job.specialization);
  }

  @override
  void didUpdateWidget(covariant JobCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job.id != widget.job.id) {
      _localBanner = BannerSelector.getRandomBanner(
          widget.job.careerField, widget.job.specialization);
    }
  }

  void _onScroll() {
    widget.scrollNotifier?.value = _scroll.offset;
    final bottom = _scroll.offset >= _scroll.position.maxScrollExtent - 80;
    if (bottom != _atBottom) setState(() => _atBottom = bottom);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x18FFFFFF), Color(0x08FFFFFF)],
            ),
            border: Border.all(
              color: kGoldDim.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: kGold.withOpacity(0.04),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildContent()),
              SliverToBoxAdapter(child: _buildDecideBanner()),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Hero ────────────────────────────────────────────────
  Widget _buildHero() {
    final hasImage = widget.job.imageUrl.isNotEmpty;
    final hasLocalBanner = _localBanner != null;

    return SizedBox(
      height: 230,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          if (hasImage)
            widget.job.imageUrl.startsWith('assets/')
                ? Image.asset(
                    widget.job.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => hasLocalBanner
                        ? Image.asset(_localBanner!, fit: BoxFit.cover)
                        : _gradientHero(),
                  )
                : Image.network(
                    widget.job.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => hasLocalBanner
                        ? Image.asset(_localBanner!, fit: BoxFit.cover)
                        : _gradientHero(),
                  )
          else if (hasLocalBanner)
            Image.asset(_localBanner!, fit: BoxFit.cover)
          else
            _gradientHero(),

          // Scrim
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.3, 1.0],
                colors: [Colors.transparent, Color(0xEE060B18)],
              ),
            ),
          ),

          // Vibe tag — top left
          if (widget.job.vibeTag.isNotEmpty)
            Positioned(
              top: 16,
              left: 16,
              child: _glassBadge('✦ ${widget.job.vibeTag}'),
            ),

          // Match score — top right
          Positioned(
            top: 16,
            right: 16,
            child: _goldBadge(widget.job.matchPercent),
          ),

          // Company info — bottom
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Logo container
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: kGoldDim.withOpacity(0.4), width: 1),
                  ),
                  child: Center(
                    child: Text(widget.job.logoEmoji,
                        style: const TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.job.company,
                        style: GoogleFonts.outfit(
                          color: kCream,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.job.postedDate.isNotEmpty)
                        Text(
                          widget.job.postedDate,
                          style:
                              GoogleFonts.outfit(color: kGoldDim, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                // Scroll hint
                Column(
                  children: [
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: kGold.withOpacity(0.7), size: 20),
                    Text('Scroll',
                        style:
                            GoogleFonts.outfit(color: kGoldDim, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1A3A5C),
            Color(0xFF0D2540),
            kBg1,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(widget.job.logoEmoji, style: const TextStyle(fontSize: 72)),
      ),
    );
  }

  Widget _glassBadge(String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGoldDim.withOpacity(0.4)),
          ),
          child: Text(text,
              style: GoogleFonts.outfit(
                  color: kGoldLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _goldBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: kGoldGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: kGold.withOpacity(0.3), blurRadius: 8),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
            color: kBg1, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  // ─── Content ─────────────────────────────────────────────
  Widget _buildContent() {
    final hasBullets = widget.job.summaryBullets.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Job title
          Text(widget.job.title,
              style: GoogleFonts.outfit(
                color: kCream,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.2,
              )),
          const SizedBox(height: 14),

          // Info chips
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(Icons.location_on_outlined, widget.job.location),
            _chip(Icons.work_outline, widget.job.jobType),
            _chip(Icons.laptop_mac_outlined, widget.job.workMode),
            if (widget.job.salaryRange.isNotEmpty)
              _chip(Icons.monetization_on_outlined, widget.job.salaryRange),
          ]),

          const SizedBox(height: 22),
          _sectionDivider('AT A GLANCE'),
          const SizedBox(height: 12),

          // AI bullets
          if (hasBullets)
            ...widget.job.summaryBullets.map(_bulletRow)
          else
            Text(widget.job.description, style: kBody(14, opacity: 0.7)),

          if (hasBullets) ...[
            const SizedBox(height: 22),
            _sectionDivider('FULL DESCRIPTION'),
            const SizedBox(height: 12),
            Text(widget.job.description, style: kBody(14, opacity: 0.65)),
          ],

          const SizedBox(height: 22),
          _sectionDivider('REQUIRED SKILLS'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.job.requiredSkills.map(_skillChip).toList(),
          ),
          const SizedBox(height: 24),
          Divider(color: kGoldDim.withOpacity(0.2)),
        ],
      ),
    );
  }

  Widget _sectionDivider(String label) {
    return Row(
      children: [
        Text(label, style: kLabel(10)),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: kGoldDim.withOpacity(0.25))),
      ],
    );
  }

  Widget _bulletRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 10),
            width: 5,
            height: 5,
            decoration:
                const BoxDecoration(color: kGold, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(text, style: kBody(14, opacity: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kGlassBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGoldDim.withOpacity(0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: kGold.withOpacity(0.7)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                style: GoogleFonts.outfit(
                    color: kCream.withOpacity(0.75), fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _skillChip(String skill) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: kGold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withOpacity(0.3), width: 1),
      ),
      child: Text(skill,
          style: GoogleFonts.outfit(
              color: kGoldLight, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  // ─── Decide Banner ────────────────────────────────────────
  Widget _buildDecideBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kGoldDim.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _decideButton(
                  icon: Icons.close_rounded,
                  label: 'Pass',
                  color: const Color(0xFFFF5252),
                  onTap: widget.onSwipeLeft,
                ),
                Container(
                    width: 1, height: 40, color: kGoldDim.withOpacity(0.3)),
                _decideButton(
                  icon: Icons.check_rounded,
                  label: 'Apply',
                  color: const Color(0xFF4CAF50),
                  onTap: widget.onSwipeRight,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _decideButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return _AnimatedDecideButton(
      icon: icon,
      label: label,
      color: color,
      onTap: onTap,
    );
  }
}

/// Animated decide button with scale-bounce on tap for tactile feedback.
class _AnimatedDecideButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AnimatedDecideButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  State<_AnimatedDecideButton> createState() => _AnimatedDecideButtonState();
}

class _AnimatedDecideButtonState extends State<_AnimatedDecideButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _ctrl.forward();
  void _onTapUp(_) async {
    await _ctrl.reverse();
    widget.onTap?.call();
  }
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(0.12),
                border: Border.all(
                    color: widget.color.withOpacity(0.6), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(widget.icon, color: widget.color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(widget.label,
                style: GoogleFonts.outfit(
                    color: widget.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
