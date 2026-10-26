part of '../fall_detection_test_dialog_feature.dart';

/// Shows fall detection test.
Future<void> showFallDetectionTest(
  BuildContext context, {
  double? sensitivity,
}) => showDialog<void>(
  context: context,
  builder: (_) => AlertDialog(
    title: const Text('Fall detection test'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: FallDetectionTestCard(initialSensitivity: sensitivity),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  ),
);
