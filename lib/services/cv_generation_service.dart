import 'package:flutter/foundation.dart';
import '../models/cv.dart';
import '../models/job.dart';
import '../models/user_profile.dart';

// ============================================================
// SERVICE: CVGenerationService
// Simulates the LLM-powered CV generation pipeline.
//
// Real implementation would call the Python backend:
//   POST /api/generate-cv { user_profile, job_description }
//
// ============================================================
// SERVICE: CVGenerationService
// Simulates the LLM-powered CV generation pipeline.
//
// 🔑 **API INTEGRATION:**
// To connect your real Python backend or directly to OpenAI,
// update `_apiKey`, `_apiUrl`, and set `_useRealAPI = true`.
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'database_service.dart';

class CVGenerationService {

  // 🟢 Fetched securely from the .env file
  static String get _apiUrl =>
      dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000/api/generate-cv';

  static String get _pdfApiUrl =>
      dotenv.env['API_URL']?.replaceAll('generate-cv', 'generate-cv-pdf')
          ?? 'http://127.0.0.1:8000/api/generate-cv-pdf';

  // 🔴 3. CHANGE TO TRUE TO USE THE REAL API
  static const bool _useRealAPI = true;

  static const int _simulatedDelayMs = 1800; // Simulates LLM latency

  /// Generates a tailored CV for a specific job based on user profile.
  /// Simulates async LLM processing with a short delay.
  Future<CV> generateCV({
    required Job job,
    required UserProfile profile,
    String cvId = '',
  }) async {
    if (_useRealAPI) {
      return await _generateCVFromAPI(job, profile, cvId);
    }

    // Fallback: Simulated generated CV
    await Future.delayed(const Duration(milliseconds: _simulatedDelayMs));

    final id = cvId.isEmpty
        ? 'cv_${job.id}_${DateTime.now().millisecondsSinceEpoch}'
        : cvId;
    final jobKeywords = _extractKeywords(job);
    final relevantExperiences =
        _filterRelevantExperiences(profile, jobKeywords);
    final highlightedSkills = _rankSkills(profile.skills, jobKeywords);

    return CV(
      id: id,
      jobId: job.id,
      jobTitle: job.title,
      company: job.company,
      content: CVContent(
        targetRole: job.title,
        summary: _buildSummary(profile, job, highlightedSkills),
        highlightedSkills: highlightedSkills,
        relevantExperiences: relevantExperiences,
        educationEntries: profile.educations
            .map((e) =>
                '${e.degree} in ${e.fieldOfStudy} — ${e.institution} (${e.graduationYear})')
            .toList(),
        keyAchievements: _buildAchievements(profile, job),
      ),
    );
  }

  /// Regenerates a CV incorporating user feedback.
  Future<CV> regenerateWithFeedback({
    required CV existingCV,
    required CVFeedback feedback,
    required Job job,
    required UserProfile profile,
  }) async {
    if (_useRealAPI) {
      return await _regenerateCVFromAPI(existingCV, feedback, job, profile);
    }

    // Fallback: Simulated regeneration with short delay
    await Future.delayed(const Duration(milliseconds: _simulatedDelayMs));

    // Apply feedback by adjusting the summary to acknowledge the request
    final updatedCV = CV(
      id: existingCV.id,
      jobId: existingCV.jobId,
      jobTitle: existingCV.jobTitle,
      company: existingCV.company,
      feedbackHistory: List.from(existingCV.feedbackHistory),
      regenerationCount: existingCV.regenerationCount,
      content: CVContent(
        targetRole: existingCV.content.targetRole,
        summary: '${existingCV.content.summary}\n\n'
            '✏️ Revised based on your feedback: "${feedback.feedbackText}"',
        highlightedSkills: existingCV.content.highlightedSkills,
        relevantExperiences: existingCV.content.relevantExperiences,
        educationEntries: existingCV.content.educationEntries,
        keyAchievements: existingCV.content.keyAchievements,
      ),
    );

    updatedCV.applyFeedback(feedback);
    return updatedCV;
  }

  // ----------------------------------------------------------
  // INTERNAL: Keyword extraction from job description
  // ----------------------------------------------------------

  List<String> _extractKeywords(Job job) {
    final keywords = <String>{};
    keywords.addAll(job.requiredSkills.map((s) => s.toLowerCase()));
    keywords.addAll(job.keywords.map((k) => k.toLowerCase()));
    keywords.add(job.industry.toLowerCase());
    return keywords.toList();
  }

  // ----------------------------------------------------------
  // INTERNAL: Filter and rank experiences by job relevance
  // ----------------------------------------------------------

  List<CVExperience> _filterRelevantExperiences(
    UserProfile profile,
    List<String> jobKeywords,
  ) {
    final result = <CVExperience>[];

    for (final exp in profile.experiences) {
      final expKeywords =
          exp.responsibilityKeywords.map((k) => k.toLowerCase()).toList();
      final relevantCount = expKeywords
          .where(
              (k) => jobKeywords.any((jk) => jk.contains(k) || k.contains(jk)))
          .length;

      if (relevantCount > 0) {
        // Build tailored bullets based on overlapping keywords
        final bullets = _buildTailoredBullets(exp, jobKeywords);
        result.add(CVExperience(
          jobTitle: exp.jobTitle,
          company: exp.company,
          duration: '${exp.startDate} – ${exp.endDate}',
          tailoredBullets: bullets,
        ));
      }
    }

    return result.isEmpty
        ? profile.experiences
            .take(2)
            .map((e) => CVExperience(
                  jobTitle: e.jobTitle,
                  company: e.company,
                  duration: '${e.startDate} – ${e.endDate}',
                  tailoredBullets: [e.description],
                ))
            .toList()
        : result;
  }

  List<String> _buildTailoredBullets(Experience exp, List<String> jobKeywords) {
    return [
      '${exp.description} Leveraged ${exp.responsibilityKeywords.take(3).join(", ")} to deliver results.',
      'Collaborated with cross-functional teams in a fast-paced environment.',
    ];
  }

  // ----------------------------------------------------------
  // ACTUAL API IMPLEMENTATION SKELETON
  // ----------------------------------------------------------

  Future<CV> _generateCVFromAPI(
      Job job, UserProfile profile, String cvId) async {
    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'job': job.toJson(),
              'user_profile': profile.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = CVContent.fromJson(data);

        final id = cvId.isEmpty
            ? 'cv_${job.id}_${DateTime.now().millisecondsSinceEpoch}'
            : cvId;

        return CV(
          id: id,
          jobId: job.id,
          jobTitle: job.title,
          company: job.company,
          content: content,
        );
      } else {
        throw Exception('CV generation failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('CV API Error: $e');
      rethrow;
    }
  }

  Future<CV> _regenerateCVFromAPI(
      CV cv, CVFeedback fb, Job job, UserProfile profile) async {
    try {
      // Assuming your FastAPI regeneration endpoint is named regenerate-cv
      final regenUrl = _apiUrl.replaceAll('generate-cv', 'regenerate-cv');

      final response = await http.post(
        Uri.parse(regenUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'existing_content': {
            'summary': cv.content.summary,
            'skills': cv.content.highlightedSkills,
            'experiences': cv.content.relevantExperiences
                .map((e) => {
                      'jobTitle': e.jobTitle,
                      'company': e.company,
                      'startDate': e.duration.split(' - ').first,
                      'endDate': e.duration.split(' - ').length > 1
                          ? e.duration.split(' - ').last
                          : '',
                      'achievements': e.tailoredBullets,
                    })
                .toList(),
          },
          'feedback_text': fb.feedbackText,
          'job': job.toJson(),
          'user_profile': profile.toJson(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updatedContent = CVContent.fromJson(data);

        final updatedCV = CV(
          id: cv.id,
          jobId: cv.jobId,
          jobTitle: cv.jobTitle,
          company: cv.company,
          content: updatedContent,
          feedbackHistory: List.from(cv.feedbackHistory),
          regenerationCount: cv.regenerationCount,
        );
        updatedCV.applyFeedback(fb);
        return updatedCV;
      } else {
        throw Exception('API regeneration failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('API Error: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // INTERNAL: Rank user skills by job relevance
  // ----------------------------------------------------------

  List<String> _rankSkills(List<String> userSkills, List<String> jobKeywords) {
    final matched = <String>[];
    final unmatched = <String>[];

    for (final skill in userSkills) {
      final lowerSkill = skill.toLowerCase();
      final isMatch = jobKeywords
          .any((kw) => kw.contains(lowerSkill) || lowerSkill.contains(kw));
      if (isMatch) {
        matched.add(skill);
      } else {
        unmatched.add(skill);
      }
    }

    // Return matched first, then up to 3 others for breadth
    return [...matched, ...unmatched.take(3)];
  }

  // ----------------------------------------------------------
  // INTERNAL: Generate professional summary
  // ----------------------------------------------------------

  String _buildSummary(UserProfile profile, Job job, List<String> skills) {
    final topSkills = skills.take(4).join(', ');
    return 'Results-driven professional with proven experience in $topSkills. '
        'Seeking the ${job.title} role at ${job.company} to leverage expertise in '
        '${profile.careerFields.join(" and ")} within the ${job.industry} sector. '
        'Passionate about delivering high-impact solutions in ${job.workMode} environments.';
  }

  // ----------------------------------------------------------
  // INTERNAL: Build key achievements relevant to the job
  // ----------------------------------------------------------

  List<String> _buildAchievements(UserProfile profile, Job job) {
    return [
      'Contributed to projects spanning ${profile.careerFields.join(" and ")} domains',
      'Demonstrated proficiency in ${job.requiredSkills.take(3).join(", ")}',
      'Adapted to ${job.workMode} work environment across multiple project cycles',
    ];
  }

  // ----------------------------------------------------------
  // PDF DOWNLOAD: Generate ATS PDF and open on device
  // ----------------------------------------------------------

  Future<String?> downloadCVPdf({
    required CV cv,
    required UserProfile profile,
    required Job job,
  }) async {
    try {
      final experiences = cv.content.relevantExperiences.map((e) {
        final parts = e.duration.split(' - ');
        return {
          'jobTitle': e.jobTitle,
          'company': e.company,
          'startDate': parts.isNotEmpty ? parts.first : '',
          'endDate': parts.length > 1 ? parts.last : '',
          'achievements': e.tailoredBullets,
        };
      }).toList();

      final educationEntries = profile.educations
          .map((e) => '${e.degree} in ${e.fieldOfStudy} — ${e.institution} (${e.graduationYear})')
          .toList();

      final response = await http.post(
        Uri.parse(_pdfApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'summary': cv.content.summary,
          'skills': cv.content.highlightedSkills,
          'experiences': experiences,
          'education_entries': educationEntries,
          'candidate_name': profile.name,
          'candidate_email': profile.email,
          'candidate_phone': profile.phone,
          'candidate_location': profile.location,
          'target_role': job.title,
          'target_company': job.company,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final safeName =
            '${profile.name.replaceAll(' ', '_')}_${job.company.replaceAll(' ', '_')}.pdf';
        final file = File('${dir.path}/$safeName');
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(file.path);
        return file.path;
      } else {
        debugPrint('PDF generation failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('PDF download error: \$e');
      return null;
    }
  }
}
// ============================================================

// ============================================================
// SERVICE: AppState (Global State Provider)
// Central state: matched jobs, CVs, and swipe history.
// ============================================================

class AppState extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  final List<Job> _matchedJobs = [];
  final Map<String, CV> _generatedCVs = {};
  bool _isLoadingMatches = true;

  bool get isLoadingMatches => _isLoadingMatches;
  List<Job> get matchedJobs => List.unmodifiable(_matchedJobs);
  Map<String, CV> get generatedCVs => Map.unmodifiable(_generatedCVs);

  AppState() {
    _initMatches();
  }

  Future<void> _initMatches() async {
    final data = await _dbService.loadUserMatches();
    _matchedJobs.addAll(data['jobs'] as List<Job>);
    _generatedCVs.addAll(data['cvs'] as Map<String, CV>);
    _isLoadingMatches = false;
    notifyListeners();
  }

  /// Adds a liked job and its generated CV to matched list.
  void addMatch(Job job, CV cv) {
    if (!_matchedJobs.any((j) => j.id == job.id)) {
      _matchedJobs.add(job);
    }
    _generatedCVs[job.id] = cv;
    notifyListeners();
    _dbService.saveMatch(job, cv);
  }

  /// Adds a job immediately on swipe-right, before CV is generated.
  /// The CV will be attached later via updateCV() when generation completes.
  void addMatchWithoutCV(Job job) {
    if (!_matchedJobs.any((j) => j.id == job.id)) {
      _matchedJobs.add(job);
      notifyListeners();
      _dbService.saveMatch(job); // Save job without CV for now
    }
  }

  /// Updates an existing CV (after regeneration or PDF download).
  void updateCV(String jobId, CV updatedCV) {
    _generatedCVs[jobId] = updatedCV;
    notifyListeners();
    
    // Find the corresponding job to update the DB
    final job = _matchedJobs.firstWhere((j) => j.id == jobId, orElse: () => _matchedJobs.first);
    if (job.id == jobId) {
      _dbService.saveMatch(job, updatedCV);
    }
  }

  /// Returns the CV for a given job id, or null.
  CV? getCVForJob(String jobId) => _generatedCVs[jobId];

  /// Removes a job from matched list.
  void removeMatch(String jobId) {
    _matchedJobs.removeWhere((j) => j.id == jobId);
    _generatedCVs.remove(jobId);
    notifyListeners();
    _dbService.deleteMatch(jobId);
  }
}
