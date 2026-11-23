import 'package:flutter/material.dart';

Future<TimeOfDay?> showHikeTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    // The keyboard layout has a fixed minimum height. Smaller system text
    // makes the stock dialog's maximum height smaller than that minimum.
    builder: (context, child) =>
        MediaQuery.withClampedTextScaling(minScaleFactor: 1, child: child!),
  );
}
