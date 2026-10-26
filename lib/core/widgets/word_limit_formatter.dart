import 'package:flutter/services.dart';

/// Computes count words.
int countWords(String text) =>
    RegExp(r'\S+', unicode: true).allMatches(text).length;

/// Keep the first [maxWords] words on paste, without interrupting IME composition.
class WordLimitTextInputFormatter extends TextInputFormatter {
  /// Creates word limit text input formatter.
  WordLimitTextInputFormatter(this.maxWords) : assert(maxWords > 0);
  final int maxWords;

  /// Formats edit update.
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final words = RegExp(
      r'\S+',
      unicode: true,
    ).allMatches(newValue.text).toList();
    if (words.length <= maxWords) return newValue;
    // Restored drafts can predate this limit. Shortening one must not silently
    // remove its ending on the first keystroke.
    final oldCount = countWords(oldValue.text);
    if (oldValue.composing.isCollapsed && oldCount > maxWords) {
      return words.length <= oldCount ? newValue : oldValue;
    }
    if (oldValue.composing.isCollapsed &&
        oldValue.selection.isValid &&
        oldValue.selection.end < oldValue.text.length) {
      return oldValue;
    }
    final end = words[maxWords - 1].end;
    return TextEditingValue(
      text: newValue.text.substring(0, end),
      selection: TextSelection(
        baseOffset: newValue.selection.baseOffset.clamp(0, end),
        extentOffset: newValue.selection.extentOffset.clamp(0, end),
      ),
    );
  }
}
