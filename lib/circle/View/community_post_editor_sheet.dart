import 'package:flutter/material.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../core/widgets/section_label.dart';
import '../Model/community_post_limits.dart';
import '../ModelView/community_post_editor_view_model.dart';

/// Edits an existing story without changing its hike or recorded route.
class CommunityPostEditorSheet extends StatefulWidget {
  /// Creates the author's editor from a fresh canonical post.
  const CommunityPostEditorSheet({
    super.key,
    required this.repository,
    required this.session,
    required this.original,
  });

  final HikerCircleFirebaseRepository repository;
  final AppSession session;
  final Map<String, dynamic> original;

  /// Creates the editor's text controller and presentation state.
  @override
  State<CommunityPostEditorSheet> createState() =>
      _CommunityPostEditorSheetState();
}

/// Presents edits and delegates validation and saving to the ViewModel.
class _CommunityPostEditorSheetState extends State<CommunityPostEditorSheet> {
  late final CommunityPostEditorViewModel _model;
  late final TextEditingController _caption;

  /// Starts with the confirmed caption and retained photos.
  @override
  void initState() {
    super.initState();
    _model = CommunityPostEditorViewModel(
      repository: widget.repository,
      session: widget.session,
      original: widget.original,
    );
    _caption = TextEditingController(text: _model.caption);
  }

  /// Releases resources when the sheet closes.
  @override
  void dispose() {
    _model.dispose();
    _caption.dispose();
    super.dispose();
  }

  /// Closes only after a confirmed save.
  Future<void> _save() async {
    _model.caption = _caption.text;
    final saved = await _model.save();
    if (mounted && saved != null) Navigator.of(context).pop(saved);
  }

  /// Builds a scrollable editor above the keyboard.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => PopScope(
      canPop: !_model.saving,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit story',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close editor',
                      onPressed: _model.saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionLabel(label: 'YOUR STORY'),
                const SizedBox(height: 8),
                TextField(
                  controller: _caption,
                  enabled: !_model.saving,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: communityPostCaptionLimit,
                  decoration: const InputDecoration(
                    hintText: 'Share your experience',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                ),
                if (_model.imageUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionLabel(label: 'PHOTOS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final url in _model.imageUrls)
                        SizedBox(
                          width: 96,
                          height: 96,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.image_outlined),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton.filled(
                                  tooltip: 'Remove photo',
                                  onPressed: _model.saving
                                      ? null
                                      : () => _model.removePhoto(url),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (_model.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _model.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _model.saving ? null : _save,
                  icon: _model.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_model.saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
