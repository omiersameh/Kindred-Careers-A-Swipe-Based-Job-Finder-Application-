import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../config/demo_config.dart';
import '../../models/cv.dart';
import '../../models/job.dart';
import '../../models/user_profile.dart';

// ============================================================
// SERVICE: MockCVService
// Simulates CV generation in Demo Mode.
//
// On swipe-right:
//  1. Shows a 1.5-second delay (simulating AI processing)
//  2. Loads a pre-compiled PDF from assets/mock_cvs/
//  3. Creates a CV object for the Matches tab
// ============================================================

class MockCVService {
  /// Simulates CV generation with a 1.5s delay, then loads a pre-built PDF.
  /// Returns a [CV] object for the Matches tab.
  Future<CV> generateMockCV({
    required Job job,
    required UserProfile profile,
    required int jobIndex,
  }) async {
    // ── Step 1: Simulate AI processing latency ───────────────────────
    await Future.delayed(const Duration(milliseconds: 1500));

    // ── Step 2: Build a CV object with realistic mock content ────────
    final cvId = 'mock_cv_${job.id}_${DateTime.now().millisecondsSinceEpoch}';

    return CV(
      id: cvId,
      jobId: job.id,
      jobTitle: job.title,
      company: job.company,
      content: CVContent(
        targetRole: job.title,
        summary: 'Results-driven professional with proven expertise in '
            '${profile.skills.take(4).join(", ")}. Seeking the ${job.title} role '
            'at ${job.company} to leverage experience in '
            '${profile.careerFields.join(" and ")} within the ${job.industry} sector.',
        highlightedSkills: profile.skills.take(6).toList(),
        relevantExperiences: profile.experiences
            .take(2)
            .map((e) => CVExperience(
                  jobTitle: e.jobTitle,
                  company: e.company,
                  duration: '${e.startDate} – ${e.endDate}',
                  tailoredBullets: [
                    e.description,
                    'Demonstrated proficiency in ${job.requiredSkills.take(2).join(" and ")}.',
                  ],
                ))
            .toList(),
        educationEntries: profile.educations
            .map((e) =>
                '${e.degree} in ${e.fieldOfStudy} — ${e.institution} (${e.graduationYear})')
            .toList(),
        keyAchievements: [
          'Contributed to projects spanning ${profile.careerFields.join(" and ")} domains',
          'Demonstrated proficiency in ${job.requiredSkills.take(3).join(", ")}',
          'Adapted to ${job.workMode} work environment across multiple project cycles',
        ],
      ),
    );
  }

  /// Loads and opens the pre-compiled mock PDF for the given member + job index.
  /// Returns the file path on success, or null on failure.
  Future<String?> openMockPdf({required int jobIndex}) async {
    try {
      final assetPath = DemoConfig.mockCvPath(jobIndex);
      debugPrint('📄 [MockCV] Loading PDF: $assetPath');

      // Load from assets and write to a temp file (assets can't be opened directly)
      final data = await rootBundle.load(assetPath);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'm${DemoConfig.currentMember}_job$jobIndex.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(data.buffer.asUint8List());

      // Open with system PDF viewer
      await OpenFile.open(file.path);
      debugPrint('✅ [MockCV] Opened PDF: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('❌ [MockCV] Failed to open PDF: $e');
      return null;
    }
  }
}
