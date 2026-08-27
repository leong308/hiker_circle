import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';

class TeamFormedNamingDialog extends StatefulWidget {
  const TeamFormedNamingDialog({
    super.key,
    required this.joinedHikerName,
    required this.trailName,
    required this.initialName,
    required this.onSubmit,
  });

  final String joinedHikerName;
  final String trailName;
  final String initialName;
  final Future<void> Function(String name) onSubmit;

  @override
  State<TeamFormedNamingDialog> createState() => _TeamFormedNamingDialogState();
}

class _TeamFormedNamingDialogState extends State<TeamFormedNamingDialog> {
  static const _green = Color(0xFF34A853);
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.length < 2) {
      setState(() => _errorMessage = 'Enter at least 2 characters.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.onSubmit(name);
      if (mounted) Navigator.of(context).pop(true);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to create the group chat right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF141C17) : Colors.white;
    final textColor = isDark
        ? const Color(0xFFEAF4EE)
        : const Color(0xFF111111);
    final secondary = isDark
        ? const Color(0xFFA8B8AE)
        : const Color(0xFF6E6E73);
    final joinedName = widget.joinedHikerName.trim().isEmpty
        ? 'A hiker'
        : widget.joinedHikerName.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF183625)
                          : const Color(0xFFEAF7EE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: _green,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your hiking team is formed',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$joinedName joined ${widget.trailName}.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: secondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF101813)
                      : const Color(0xFFF5F7F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_rounded,
                      color: _green,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A private group chat is ready. Give your team a name to continue.',
                        style: TextStyle(color: textColor, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'GROUP CHAT NAME',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('team-group-name-field'),
                controller: _nameController,
                autofocus: true,
                enabled: !_isSaving,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isSaving ? null : _save(),
                decoration: InputDecoration(
                  hintText: 'e.g. Summit Sunrise Crew',
                  errorText: _errorMessage,
                  counterText: '',
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF101813)
                      : const Color(0xFFF5F7F5),
                  prefixIcon: const Icon(Icons.edit_rounded, color: _green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _green, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('create-team-group-chat-button'),
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _green.withValues(alpha: 0.55),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  _isSaving ? 'Creating chat...' : 'Create group chat',
                ),
              ),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text('Not now', style: TextStyle(color: secondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
