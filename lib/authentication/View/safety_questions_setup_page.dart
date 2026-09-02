import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/loading_toast.dart';

import '../Model/safety_questions.dart';

class SafetyQuestionsSetupPage extends StatefulWidget {
  const SafetyQuestionsSetupPage({super.key, required this.onSubmitted});

  final Future<void> Function() onSubmitted;

  @override
  State<SafetyQuestionsSetupPage> createState() =>
      _SafetyQuestionsSetupPageState();
}

class _SafetyQuestionsSetupPageState extends State<SafetyQuestionsSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _answer1Controller = TextEditingController();
  final _answer2Controller = TextEditingController();
  String? _question1;
  String? _question2;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _answer1Controller.dispose();
    _answer2Controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_question1 == null || _question2 == null) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await FirebaseFunctions.instance
          .httpsCallable('registerSafetyQuestions')
          .call(<String, Object?>{
            'q1': _question1,
            'a1': _answer1Controller.text.trim(),
            'q2': _question2,
            'a2': _answer2Controller.text.trim(),
          });
      if (!mounted) return;
      await widget.onSubmitted();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Safety Questions',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Step 2 of 3. Choose two safety questions and provide answers. '
                          'You will need them to reset your password.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Question 1',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _question1,
                          decoration: const InputDecoration(
                            labelText: 'Select a question',
                            prefixIcon: Icon(Icons.help_outline),
                          ),
                          isExpanded: true,
                          items: safetyQuestionsList
                              .where((q) => q != _question2)
                              .map(
                                (q) => DropdownMenuItem(
                                  value: q,
                                  child: Text(
                                    q,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _question1 = v),
                          validator: (v) =>
                              v == null ? 'Select a question.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _answer1Controller,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Answer 1',
                            prefixIcon: Icon(Icons.edit),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 2) {
                              return 'Answer must be at least 2 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Question 2',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _question2,
                          decoration: const InputDecoration(
                            labelText: 'Select a different question',
                            prefixIcon: Icon(Icons.help_outline),
                          ),
                          isExpanded: true,
                          items: safetyQuestionsList
                              .where((q) => q != _question1)
                              .map(
                                (q) => DropdownMenuItem(
                                  value: q,
                                  child: Text(
                                    q,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _question2 = v),
                          validator: (v) =>
                              v == null ? 'Select a question.' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _answer2Controller,
                          enabled: !_isSaving,
                          decoration: const InputDecoration(
                            labelText: 'Answer 2',
                            prefixIcon: Icon(Icons.edit),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 2) {
                              return 'Answer must be at least 2 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.onErrorContainer),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _submit,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(_isSaving ? 'Saving...' : 'Continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isSaving)
              HikerCircleLoadingToastOverlay(
                message: 'Saving your safety questions…',
                detail:
                    'Securing your recovery options. This may take a moment.',
                timeout: const Duration(seconds: 30),
                onTimeout: () {
                  if (!mounted || !_isSaving) return;
                  setState(() {
                    _isSaving = false;
                    _error = 'Saving timed out. Please try again.';
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
