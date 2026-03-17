// ============================================================
// MODEL: SwipeAction
// Records every swipe gesture the user makes on a job card.
// This data feeds the LSTM recommendation engine.
// ============================================================

enum SwipeDirection { left, right }

class SwipeAction {
  final String id;
  final String jobId;
  final String jobTitle;
  final String company;
  final SwipeDirection direction;
  final DateTime timestamp;

  SwipeAction({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.company,
    required this.direction,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Returns true if this was a "like" (swipe right) action.
  bool get isLike => direction == SwipeDirection.right;

  /// Returns true if this was a "pass" (swipe left) action.
  bool get isPass => direction == SwipeDirection.left;

  @override
  String toString() =>
      'SwipeAction($jobTitle: ${direction.name} at ${timestamp.toIso8601String()})';
}
