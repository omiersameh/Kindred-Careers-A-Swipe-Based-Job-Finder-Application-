import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'preview_questionnaire_screen.dart';
import 'services/user_profile_service.dart';
import 'models/user_profile.dart';

class MockUserProfileService extends ChangeNotifier implements UserProfileService {
  @override
  UserProfile profile = UserProfile(
    id: 'guest',
    name: 'Omier Sameh',
    email: 'omier.sameh@kindred.com',
  );

  @override
  Future<void> loadProfile() async {}

  @override
  void updateProfile(UserProfile updatedProfile) {
    profile = updatedProfile;
    notifyListeners();
  }

  @override
  void addSkill(String skill) {}
  @override
  void removeSkill(String skill) {}
  @override
  void addCareerField(String field) {}
  @override
  void removeCareerField(String field) {}
  @override
  void addExperience(Experience exp) {}
  @override
  void removeExperience(String expId) {}
  @override
  void addEducation(Education edu) {}
  @override
  void removeEducation(String eduId) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProfileService>(
          create: (_) => MockUserProfileService(),
        ),
      ],
      child: MaterialApp(
        title: 'Questionnaire Preview',
        theme: buildAppTheme(),
        home: const PreviewQuestionnaireScreen(),
        routes: {
          '/main': (_) => const Scaffold(
                body: Center(
                  child: Text(
                    'Profile Questionnaire Submitted Successfully!',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
        },
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
