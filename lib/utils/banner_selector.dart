import 'dart:math';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;

/// Selects a random banner image from assets/images/banners/{field}/{specialization}/
///
/// Pipeline:
///   1. On app startup, [init()] uses Flutter's AssetManifest API to discover
///      every image file under assets/images/banners/ and indexes them by
///      "field/specialization".
///   2. When a job card needs a banner, [getRandomBanner(field, specialization)]
///      sanitizes the strings to handle LLM variations (slashes → ampersands)
///      and returns a random image path from the matching folder.
///   3. Falls back to: any image in the same field → null (gradient).
class BannerSelector {
  static final Map<String, List<String>> _assetCache = {};
  static bool _isLoaded = false;

  /// Call once at app startup (before runApp or in main).
  static Future<void> init() async {
    if (_isLoaded) return;

    try {
      // Use Flutter's official AssetManifest API (works with both .json and .bin)
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      print('[BannerSelector] AssetManifest loaded — ${allAssets.length} total assets');

      int imageCount = 0;
      for (final rawKey in allAssets) {
        // Decode URL-encoded paths (%20 → space, %26 → &)
        final key = Uri.decodeFull(rawKey);

        if (!key.startsWith('assets/images/banners/')) continue;

        // Expected format: assets/images/banners/Technology/AI & ML Engineer/ml1.jpg
        //                  [0]    [1]     [2]      [3]         [4]             [5]
        final parts = key.split('/');
        if (parts.length < 6) continue; // Need at least field + spec + filename

        final field = parts[3];
        // Specialization folder may have sub-paths; join everything between
        // the field (index 3) and the filename (last element).
        final spec = parts.sublist(4, parts.length - 1).join('/');

        if (spec.isEmpty) continue; // Skip files directly in field folder

        final lookupKey = '$field/$spec';
        _assetCache.putIfAbsent(lookupKey, () => []).add(key);
        imageCount++;
      }

      _isLoaded = true;
      print('[BannerSelector] ✅ Ready! Indexed $imageCount images across ${_assetCache.length} specializations');

      // Log all indexed entries for debugging
      for (final entry in _assetCache.entries) {
        print('[BannerSelector]   ${entry.key} → ${entry.value.length} images');
      }
    } catch (e, st) {
      print('[BannerSelector] FATAL init error: $e');
      print('[BannerSelector] Stack trace: $st');
      _isLoaded = false;
    }
  }

  /// Normalizes LLM-generated field/specialization strings to match folder names.
  ///
  /// Handles common LLM output variations:
  ///   "AI/ML Engineer"       → "AI & ML Engineer"
  ///   "AI _ ML Engineer"     → "AI & ML Engineer"
  ///   "AI  &  ML Engineer"   → "AI & ML Engineer"
  static String _sanitize(String input) {
    return input
        .replaceAll('/', ' & ')     // LLMs love slashes
        .replaceAll('\\', ' & ')    // Backslashes too
        .replaceAll(' _ ', ' & ')   // Our old underscore convention
        .replaceAll(RegExp(r'\s*&\s*'), ' & ') // Normalize spacing around &
        .replaceAll(RegExp(r'\s{2,}'), ' ')     // Collapse multiple spaces
        .trim();
  }

  /// Returns a random image asset path for the given job's field + specialization.
  ///
  /// Returns null if no matching images exist → the UI should show a fallback gradient.
  static String? getRandomBanner(String field, String specialization) {
    if (!_isLoaded) {
      print('[BannerSelector] Not loaded yet — returning null');
      return null;
    }

    if (field.isEmpty && specialization.isEmpty) return null;

    final safeField = _sanitize(field);
    final safeSpec = _sanitize(specialization);
    final exactKey = '$safeField/$safeSpec';

    // ── Try 1: Exact field/specialization match ──
    final exactMatches = _assetCache[exactKey];
    if (exactMatches != null && exactMatches.isNotEmpty) {
      final pick = exactMatches[Random().nextInt(exactMatches.length)];
      print('[BannerSelector] HIT $exactKey → $pick');
      return pick;
    }

    // ── Try 2: Case-insensitive match (LLM casing varies) ──
    final lowerKey = exactKey.toLowerCase();
    for (final entry in _assetCache.entries) {
      if (entry.key.toLowerCase() == lowerKey && entry.value.isNotEmpty) {
        final pick = entry.value[Random().nextInt(entry.value.length)];
        print('[BannerSelector] CASE-INSENSITIVE HIT ${entry.key} → $pick');
        return pick;
      }
    }

    // ── Try 3: Partial specialization match (substring) ──
    for (final entry in _assetCache.entries) {
      if (entry.key.startsWith('$safeField/')) {
        final folderSpec = entry.key.split('/').last.toLowerCase();
        final querySpec = safeSpec.toLowerCase();
        if (folderSpec.contains(querySpec) || querySpec.contains(folderSpec)) {
          if (entry.value.isNotEmpty) {
            final pick = entry.value[Random().nextInt(entry.value.length)];
            print('[BannerSelector] PARTIAL HIT ${entry.key} → $pick');
            return pick;
          }
        }
      }
    }

    // ── Try 4: Any image from the same career field ──
    final fieldMatches = _assetCache.entries
        .where((e) => e.key.startsWith('$safeField/'))
        .expand((e) => e.value)
        .toList();

    if (fieldMatches.isNotEmpty) {
      final pick = fieldMatches[Random().nextInt(fieldMatches.length)];
      print('[BannerSelector] FIELD FALLBACK $safeField → $pick');
      return pick;
    }

    print('[BannerSelector] MISS for $exactKey — no images at all');
    return null;
  }
}
