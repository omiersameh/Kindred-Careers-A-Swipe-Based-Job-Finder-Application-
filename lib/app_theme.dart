import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================
// APP THEME — Kindred Careers 2.0
// Aesthetic: Deep navy/teal/purple gradient + Gold accents
//            + Glassmorphism cards
// ============================================================

// ── Palette ──────────────────────────────────────────────────
const kGold = Color(0xFFC9A84C); // Primary gold accent
const kGoldLight = Color(0xFFE8C878); // Light gold for text / highlights
const kGoldDim = Color(0xFF8A6D2A); // Muted gold for borders
const kCream = Color(0xFFFFFFFF); // White body text instead of cream

const kBg1 = Color(0xFF121212); // Darkest gray
const kBg2 = Color(0xFF1A1A1A); // Mid gray
const kBg3 = Color(0xFF222222); // Lighter gray
const kBg4 = Color(0xFF191919); // Bottom shade

const kGlassBg = Color(0x0DFFFFFF); // 5% white = glass surface
const kGlassBorder = Color(0x1AFFFFFF); // 10% white = glass edge
const kGlassHigh = Color(0x0AFFD700); // Gold-tinted glass highlight

// ── Gradients ─────────────────────────────────────────────────
const kBackgroundGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kBg1, kBg2, kBg3, kBg4],
  stops: [0.0, 0.35, 0.7, 1.0],
);

const kGoldGradient = LinearGradient(
  colors: [Color(0xFFE8C878), Color(0xFFC9A84C), Color(0xFFA07828)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kGoldShimmer = LinearGradient(
  colors: [Color(0xFFA07828), Color(0xFFE8C878), Color(0xFFC9A84C)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// ── Text Styles ───────────────────────────────────────────────
TextStyle kHeadline(double size, {FontWeight fw = FontWeight.w800}) =>
    GoogleFonts.outfit(
      color: kGoldLight,
      fontSize: size,
      fontWeight: fw,
      letterSpacing: -0.3,
    );

TextStyle kBody(double size, {Color color = kCream, double opacity = 1}) =>
    GoogleFonts.outfit(
      color: color.withOpacity(opacity),
      fontSize: size,
      height: 1.5,
    );

TextStyle kLabel(double size, {Color color = kGold}) => GoogleFonts.outfit(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
    );

// ── Glass Card Decoration ─────────────────────────────────────
BoxDecoration glassCard({
  double borderRadius = 20,
  Color border = kGlassBorder,
  Color bg = kGlassBg,
}) =>
    BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: border, width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );

// ── Gold Border Decoration ────────────────────────────────────
BoxDecoration goldBorderCard({double borderRadius = 16}) => BoxDecoration(
      color: kGlassBg,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: kGoldDim.withOpacity(0.5), width: 1),
    );

// ── ThemeData ─────────────────────────────────────────────────
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBg1,
    colorScheme: const ColorScheme.dark(
      primary: kGold,
      secondary: kGoldLight,
      surface: kBg2,
    ),
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFF1A1200).withOpacity(0.9),
    ),
  );
}
