// HikerFeedbackCaptureForm collects a screenshot preview before the separate feedback upload step.
import 'dart:async';

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

/// Capture is only a preview step; the separate review page performs upload.
class HikerFeedbackCaptureForm extends StatefulWidget {
  const HikerFeedbackCaptureForm({
    super.key,
    required this.onSubmit,
    this.scrollController,
  });
  final OnSubmit onSubmit;
  final ScrollController? scrollController;

  @override
  State<HikerFeedbackCaptureForm> createState() =>
      _HikerFeedbackCaptureFormState();
}

class _HikerFeedbackCaptureFormState extends State<HikerFeedbackCaptureForm> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_text.text).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (mounted) BetterFeedback.of(context).hide();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not capture this screen. Try again or close capture and write feedback without a screenshot.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          children: [
            const Text(
              'Mark the issue, then review your feedback',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
            TextField(
              controller: _text,
              readOnly: _busy,
              maxLength: 4000,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'What happened? (optional here)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _preview,
            child: Text(_busy ? 'Preparing preview…' : 'Review screenshot'),
          ),
        ),
      ),
    ],
  );
}
