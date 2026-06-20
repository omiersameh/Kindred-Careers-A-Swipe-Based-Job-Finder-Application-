// ============================================================
// MODEL: UserProfile
// Represents the single comprehensive profile for each user.
// Stores career expertise, skills, education, preferences.
// ============================================================

class UserProfile {
  String id;
  String name;
  String email;
  String phone;
  String bio;
  String location;
  int age;
  List<String> skills;
  List<Experience> experiences;
  List<Education> educations;
  List<String>
      careerFields; // e.g. ["Software Engineering", "Digital Marketing"]
  Map<String, List<String>> specializations;
  List<Credential> credentials;
  List<String> preferredIndustries;
  String preferredWorkMode; // "Remote", "Hybrid", "Onsite"
  double expectedSalaryMin;
  double expectedSalaryMax;
  DateTime createdAt;
  DateTime updatedAt;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.bio = '',
    this.location = '',
    this.age = 0,
    List<String>? skills,
    List<Experience>? experiences,
    List<Education>? educations,
    List<String>? careerFields,
    Map<String, List<String>>? specializations,
    List<Credential>? credentials,
    List<String>? preferredIndustries,
    this.preferredWorkMode = 'Hybrid',
    this.expectedSalaryMin = 0,
    this.expectedSalaryMax = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : skills = skills ?? [],
        experiences = experiences ?? [],
        educations = educations ?? [],
        careerFields = careerFields ?? [],
        specializations = specializations ?? {},
        credentials = credentials ?? [],
        preferredIndustries = preferredIndustries ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Returns all keywords extracted from the profile for job matching.
  List<String> get allKeywords {
    final keywords = <String>[];
    keywords.addAll(skills);
    keywords.addAll(careerFields);
    for (final specs in specializations.values) {
      keywords.addAll(specs);
    }
    keywords.addAll(credentials.map((c) => c.title));
    keywords.addAll(preferredIndustries);
    for (final exp in experiences) {
      keywords.addAll(exp.responsibilityKeywords);
    }
    return keywords.map((k) => k.toLowerCase()).toSet().toList();
  }

  /// Creates a copy with updated fields.
  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? bio,
    String? location,
    int? age,
    List<String>? skills,
    List<Experience>? experiences,
    List<Education>? educations,
    List<String>? careerFields,
    Map<String, List<String>>? specializations,
    List<Credential>? credentials,
    List<String>? preferredIndustries,
    String? preferredWorkMode,
    double? expectedSalaryMin,
    double? expectedSalaryMax,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      age: age ?? this.age,
      skills: skills ?? List.from(this.skills),
      experiences: experiences ?? List.from(this.experiences),
      educations: educations ?? List.from(this.educations),
      careerFields: careerFields ?? List.from(this.careerFields),
      specializations: specializations ?? Map.from(this.specializations),
      credentials: credentials ?? List.from(this.credentials),
      preferredIndustries:
          preferredIndustries ?? List.from(this.preferredIndustries),
      preferredWorkMode: preferredWorkMode ?? this.preferredWorkMode,
      expectedSalaryMin: expectedSalaryMin ?? this.expectedSalaryMin,
      expectedSalaryMax: expectedSalaryMax ?? this.expectedSalaryMax,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  String toString() => 'UserProfile(name: $name, skills: $skills)';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'bio': bio,
      'location': location,
      'age': age,
      'skills': skills,
      'experiences': experiences.map((e) => e.toJson()).toList(),
      'educations': educations.map((e) => e.toJson()).toList(),
      'careerFields': careerFields,
      'specializations': specializations,
      'credentials': credentials.map((c) => c.toJson()).toList(),
      'preferredWorkMode': preferredWorkMode,
      'preferredIndustries': preferredIndustries,
      'expectedSalaryMin': expectedSalaryMin,
      'expectedSalaryMax': expectedSalaryMax,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      location: json['location'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      skills: (json['skills'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      experiences: (json['experiences'] as List<dynamic>?)
              ?.map((e) => Experience.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      educations: (json['educations'] as List<dynamic>?)
              ?.map((e) => Education.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      careerFields: (json['careerFields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      specializations: (json['specializations'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              (value as List<dynamic>).map((e) => e as String).toList(),
            ),
          ) ??
          {},
      credentials: (json['credentials'] as List<dynamic>?)
              ?.map((e) => Credential.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      preferredIndustries: (json['preferredIndustries'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      preferredWorkMode: json['preferredWorkMode'] as String? ?? 'Hybrid',
      expectedSalaryMin: (json['expectedSalaryMin'] as num?)?.toDouble() ?? 0,
      expectedSalaryMax: (json['expectedSalaryMax'] as num?)?.toDouble() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }
}

// ============================================================
// MODEL: Credential
// Represents an internship, certificate, or credential.
// ============================================================

class Credential {
  String id;
  String title;
  String issuer;
  String year;

  Credential({
    required this.id,
    required this.title,
    required this.issuer,
    required this.year,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'issuer': issuer,
      'year': year,
    };
  }

  factory Credential.fromJson(Map<String, dynamic> json) {
    return Credential(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      issuer: json['issuer'] as String? ?? '',
      year: json['year'] as String? ?? '',
    );
  }
}

// ============================================================
// MODEL: Experience
// Represents a single work experience entry in the profile.
// ============================================================

class Experience {
  String id;
  String jobTitle;
  String company;
  String startDate;
  String endDate;
  String description;
  List<String> responsibilityKeywords;

  Experience({
    required this.id,
    required this.jobTitle,
    required this.company,
    required this.startDate,
    this.endDate = 'Present',
    this.description = '',
    List<String>? responsibilityKeywords,
  }) : responsibilityKeywords = responsibilityKeywords ?? [];

  @override
  String toString() => '$jobTitle at $company ($startDate - $endDate)';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'jobTitle': jobTitle,
      'company': company,
      'startDate': startDate,
      'endDate': endDate,
      'description': description,
      'responsibilityKeywords': responsibilityKeywords,
    };
  }

  factory Experience.fromJson(Map<String, dynamic> json) {
    return Experience(
      id: json['id'] as String? ?? '',
      jobTitle: json['jobTitle'] as String? ?? '',
      company: json['company'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? 'Present',
      description: json['description'] as String? ?? '',
      responsibilityKeywords: (json['responsibilityKeywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

// ============================================================
// MODEL: Education
// Represents an education entry in the user profile.
// ============================================================

class Education {
  String id;
  String degree;
  String institution;
  String fieldOfStudy;
  String graduationYear;

  Education({
    required this.id,
    required this.degree,
    required this.institution,
    required this.fieldOfStudy,
    required this.graduationYear,
  });

  @override
  String toString() =>
      '$degree in $fieldOfStudy from $institution ($graduationYear)';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'degree': degree,
      'fieldOfStudy': fieldOfStudy,
      'institution': institution,
      'graduationYear': graduationYear,
    };
  }

  factory Education.fromJson(Map<String, dynamic> json) {
    return Education(
      id: json['id'] as String? ?? '',
      degree: json['degree'] as String? ?? '',
      institution: json['institution'] as String? ?? '',
      fieldOfStudy: json['fieldOfStudy'] as String? ?? '',
      graduationYear: json['graduationYear'] as String? ?? '',
    );
  }
}
