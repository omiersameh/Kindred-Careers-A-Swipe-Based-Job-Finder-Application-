import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';

// ============================================================
// SERVICE: UserProfileService
// State management provider for the user's single profile.
// Uses ChangeNotifier so UI rebuilds on profile updates.
// ============================================================

class UserProfileService extends ChangeNotifier {
  UserProfile _profile = _buildDefaultProfile(FirebaseAuth.instance.currentUser?.uid ?? 'user_001');

  UserProfile get profile => _profile;

  /// Loads the profile from local storage for the current user.
  Future<void> loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_profile_$uid');
    
    if (data != null) {
      try {
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        _profile = UserProfile.fromJson(decoded);
      } catch (e) {
        debugPrint('Error loading profile JSON: $e');
        _profile = _buildDefaultProfile(uid);
      }
    } else {
      _profile = _buildDefaultProfile(uid);
    }
    notifyListeners();
  }

  /// Saves the current profile to local storage.
  void _saveProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_profile_$uid', jsonEncode(_profile.toJson()));
    } catch (e) {
      debugPrint('Error saving profile: $e');
    }
  }

  /// Updates the profile and notifies all listeners.
  void updateProfile(UserProfile updatedProfile) {
    _profile = updatedProfile;
    _saveProfile();
    notifyListeners();
  }

  /// Adds a new skill to the profile.
  void addSkill(String skill) {
    if (skill.trim().isEmpty) return;
    if (_profile.skills.contains(skill.trim())) return;
    _profile = _profile.copyWith(
      skills: [..._profile.skills, skill.trim()],
    );
    _saveProfile();
    notifyListeners();
  }

  /// Removes a skill from the profile.
  void removeSkill(String skill) {
    _profile = _profile.copyWith(
      skills: _profile.skills.where((s) => s != skill).toList(),
    );
    _saveProfile();
    notifyListeners();
  }

  /// Adds a career field to the profile.
  void addCareerField(String field) {
    if (field.trim().isEmpty) return;
    if (_profile.careerFields.contains(field.trim())) return;
    _profile = _profile.copyWith(
      careerFields: [..._profile.careerFields, field.trim()],
    );
    _saveProfile();
    notifyListeners();
  }

  /// Removes a career field from the profile.
  void removeCareerField(String field) {
    _profile = _profile.copyWith(
      careerFields: _profile.careerFields.where((f) => f != field).toList(),
    );
    _saveProfile();
    notifyListeners();
  }

  /// Adds a work experience entry to the profile.
  void addExperience(Experience exp) {
    _profile = _profile.copyWith(
      experiences: [..._profile.experiences, exp],
    );
    _saveProfile();
    notifyListeners();
  }

  /// Removes an experience by its id.
  void removeExperience(String expId) {
    _profile = _profile.copyWith(
      experiences: _profile.experiences.where((e) => e.id != expId).toList(),
    );
    _saveProfile();
    notifyListeners();
  }

  /// Adds an education entry to the profile.
  void addEducation(Education edu) {
    _profile = _profile.copyWith(
      educations: [..._profile.educations, edu],
    );
    _saveProfile();
    notifyListeners();
  }

  /// Removes an education entry by its id.
  void removeEducation(String eduId) {
    _profile = _profile.copyWith(
      educations: _profile.educations.where((e) => e.id != eduId).toList(),
    );
    _saveProfile();
    notifyListeners();
  }

  // --------------------------------------------------------
  // Default profile seeded with realistic demo data
  // --------------------------------------------------------
  static UserProfile _buildDefaultProfile(String id) {
    return UserProfile(
      id: id,
      name: 'Sarah Ahmed',
      email: 'sarah.ahmed@email.com',
      phone: '+20 100 123 4567',
      bio:
          'Passionate software engineer and digital marketing enthusiast with 3+ years experience building scalable web applications and leading data-driven marketing campaigns.',
      location: 'Cairo, Egypt',
      skills: [
        'Flutter', 'Dart', 'Python', 'React',
        'Node.js', 'SQL', 'Machine Learning',
        'SEO', 'Google Analytics', 'Content Strategy',
      ],
      careerFields: ['Software Engineering', 'Digital Marketing'],
      preferredIndustries: ['Technology', 'E-Commerce', 'FinTech'],
      preferredWorkMode: 'Hybrid',
      expectedSalaryMin: 25,
      expectedSalaryMax: 55,
      experiences: [
        Experience(
          id: 'exp_001',
          jobTitle: 'Junior Flutter Developer',
          company: 'TechCairo Solutions',
          startDate: 'Jan 2023',
          endDate: 'Present',
          description: 'Built mobile apps using Flutter and Dart.',
          responsibilityKeywords: ['Flutter', 'Dart', 'Firebase', 'REST API', 'mobile'],
        ),
        Experience(
          id: 'exp_002',
          jobTitle: 'Digital Marketing Intern',
          company: 'GrowthLab Egypt',
          startDate: 'Jun 2022',
          endDate: 'Dec 2022',
          description: 'Managed SEO, Google Ads, and social media campaigns.',
          responsibilityKeywords: ['SEO', 'Google Ads', 'social media', 'analytics', 'campaigns'],
        ),
      ],
      educations: [
        Education(
          id: 'edu_001',
          degree: 'Bachelor of Science',
          institution: 'Cairo University',
          fieldOfStudy: 'Computer Science',
          graduationYear: '2022',
        ),
      ],
    );
  }
}
