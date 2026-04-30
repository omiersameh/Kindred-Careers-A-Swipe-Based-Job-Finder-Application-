// ============================================================
// MODEL: Job
// Represents a job listing fetched from the external Job API.
// Includes fields for AI matching score computation.
// ============================================================

class Job {
  final String id;
  final String title;
  final String company;
  final String location;
  final String description;
  final String industry;
  final String jobType; // "Full-Time", "Part-Time", "Contract", "Internship"
  final String workMode; // "Remote", "Hybrid", "Onsite"
  final double salaryMin;
  final double salaryMax;
  final List<String> requiredSkills;
  final List<String> keywords;
  final String logoEmoji; // Emoji placeholder for company logo
  final String postedDate;
  double matchScore; // Computed by JobRecommendationService
  // Phase 3: RAG fields
  final String imageUrl; // Company / listing image URL from scraper
  final List<String> summaryBullets; // 3-4 Gemini-generated bullet summary
  final String vibeTag; // e.g. 'Fast-paced Startup'
  final String careerField; // e.g. 'Technology'
  final String specialization; // e.g. 'Full-Stack Developer'

  Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.description,
    required this.industry,
    this.jobType = 'Full-Time',
    this.workMode = 'Hybrid',
    this.salaryMin = 0,
    this.salaryMax = 0,
    List<String>? requiredSkills,
    List<String>? keywords,
    this.logoEmoji = '🏢',
    this.postedDate = '',
    this.matchScore = 0.0,
    this.imageUrl = '',
    List<String>? summaryBullets,
    this.vibeTag = '',
    this.careerField = '',
    this.specialization = '',
  })  : requiredSkills = requiredSkills ?? [],
        keywords = keywords ?? [],
        summaryBullets = summaryBullets ?? [];

  /// Returns the formatted salary range string.
  String get salaryRange {
    if (salaryMin == 0 && salaryMax == 0) return 'Salary Not Disclosed';
    if (salaryMax == 0) return '\$${salaryMin.toStringAsFixed(0)}+';
    return '\$${salaryMin.toStringAsFixed(0)}k – \$${salaryMax.toStringAsFixed(0)}k';
  }

  /// Returns match score as a percentage string.
  /// Backend sends matchScore already in 0-100 range.
  String get matchPercent => '${matchScore.clamp(0, 100).toStringAsFixed(0)}%';

  /// Returns match score color for UI display (score is 0-100).
  int get matchColorValue {
    if (matchScore >= 75) return 0xFF4CAF50; // Green  — strong match
    if (matchScore >= 50) return 0xFF2196F3; // Blue   — good match
    if (matchScore >= 25) return 0xFFFF9800; // Orange — partial match
    return 0xFF9E9E9E; // Grey   — low match
  }

  @override
  String toString() => 'Job($title at $company, match: $matchPercent)';

  /// Converts Job object into a JSON map to send to the backend.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'company': company,
      'location': location,
      'description': description,
      'industry': industry,
      'jobType': jobType,
      'workMode': workMode,
      'minSalary': salaryMin,
      'maxSalary': salaryMax,
      'requiredSkills': requiredSkills,
      'matchScore': matchScore,
      'careerField': careerField,
      'specialization': specialization,
    };
  }

  /// Parses a Job from the backend JSON response (RAG feed).
  /// All fields use safe coercion to prevent 'int is not a subtype of String'.
  factory Job.fromJson(Map<String, dynamic> json) {
    // Safe helpers
    String str(dynamic v, [String d = '']) => v == null ? d : v.toString();
    List<String> strList(dynamic v) => v == null
        ? []
        : List<dynamic>.from(v as List).map((e) => e.toString()).toList();
    double dbl(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    return Job(
      id: str(json['id']),
      title: str(json['title']),
      company: str(json['company']),
      location: str(json['location']),
      description: str(json['description']),
      industry: str(json['industry']),
      jobType: str(json['jobType'], 'Full-Time'),
      workMode: str(json['workMode'], 'Hybrid'),
      salaryMin: dbl(json['minSalary']),
      salaryMax: dbl(json['maxSalary']),
      requiredSkills: strList(json['requiredSkills']),
      logoEmoji: str(json['logoEmoji'], '🏢'),
      postedDate: str(json['postedDate']),
      matchScore: dbl(json['matchScore']),
      imageUrl: str(json['imageUrl']),
      summaryBullets: strList(json['summaryBullets']),
      vibeTag: str(json['vibeTag']),
      careerField: str(json['careerField']),
      specialization: str(json['specialization']),
    );
  }
}
