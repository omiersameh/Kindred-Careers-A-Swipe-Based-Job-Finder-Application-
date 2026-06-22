import 'dart:async';
import 'package:flutter/material.dart';

// ============================================================
// UTILITY: DemoTypingController
// Animates text into a TextEditingController character by
// character, simulating realistic live typing for the demo.
// ============================================================

class DemoTypingController {
  /// Animates [text] into [controller] one character at a time.
  ///
  /// [delayMs] — milliseconds between each character (default 30ms).
  /// Returns a Future that completes when the full text is typed.
  /// If the widget is disposed mid-animation, the returned future
  /// still completes but stops updating the controller.
  static Future<void> typeInto(
    TextEditingController controller,
    String text, {
    int delayMs = 30,
  }) async {
    controller.clear();
    for (int i = 0; i < text.length; i++) {
      await Future.delayed(Duration(milliseconds: delayMs));
      // Guard: if the controller was disposed, stop gracefully
      try {
        controller.text = text.substring(0, i + 1);
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      } catch (_) {
        return; // Controller disposed — exit silently
      }
    }
  }

  /// Types into multiple controllers in sequence.
  /// Each entry is a (controller, text) pair.
  static Future<void> typeAll(
    List<MapEntry<TextEditingController, String>> entries, {
    int delayMs = 30,
    int gapMs = 200, // Pause between fields
  }) async {
    for (final entry in entries) {
      await typeInto(entry.key, entry.value, delayMs: delayMs);
      await Future.delayed(Duration(milliseconds: gapMs));
    }
  }
}
