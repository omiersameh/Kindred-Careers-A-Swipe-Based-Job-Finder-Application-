import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'screens/onboarding_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Onboarding Preview',
      theme: buildAppTheme(),
      home: const Scaffold(
        body: OnboardingScreen(),
      ),
      debugShowCheckedModeBanner: false,
    ),
  );
}
