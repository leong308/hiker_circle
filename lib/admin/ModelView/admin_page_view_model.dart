part of '../admin_page_feature.dart';

/// Owns the state and non-visual actions of AdminPage.
class _AdminPageStateViewModel extends ChangeNotifier {
  /// Creates admin page state view model.
  _AdminPageStateViewModel({
    required this.effectLoadAdminData,
    required this.effectShowSnack,
  });
  final Future<void> Function() effectLoadAdminData;
  final void Function(String message, {bool isError}) effectShowSnack;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Applies a state change and publishes it to listeners.
  void _publish(VoidCallback update) {
    update();
    if (!_disposed) notifyListeners();
  }

  final Map<AdminSection, String> stateSectionErrors = {};

  bool stateIsSaving = false;

  /// Returns command error message.
  String? get commandErrorMessage =>
      stateSectionErrors.isEmpty ? null : stateSectionErrors.values.join("\n");

  /// Wait for the mutation and refreshed server state before showing an administrator success message.
  Future<void> commandRunAdminAction({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (stateIsSaving) {
      return;
    }

    _publish(() {
      stateIsSaving = true;
    });
    try {
      await action();
      await effectLoadAdminData();
      if (!mounted) {
        return;
      }
      effectShowSnack(successMessage);
    } on HikerCircleFirebaseRepositoryException catch (error) {
      effectShowSnack(error.message, isError: true);
    } catch (_) {
      effectShowSnack('Admin action failed. Please try again.', isError: true);
    } finally {
      if (mounted) {
        _publish(() {
          stateIsSaving = false;
        });
      }
    }
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  int stateAdminDataRevision = 0;

  final Set<AdminSection> stateLoadingSections = {};

  final Map<AdminSection, DateTime> stateSectionLoadedAt = {};

  /// Loads section.
  Future<void> commandLoadSection<T>(
    AdminSection section,
    int revision,
    Future<T> Function() load,
    void Function(T) apply,
  ) async {
    try {
      final data = await load().timeout(const Duration(seconds: 30));
      if (!mounted || revision != stateAdminDataRevision) return;
      _publish(() {
        apply(data);
        stateSectionLoadedAt[section] = DateTime.now();
      });
    } catch (error) {
      if (!mounted || revision != stateAdminDataRevision) return;
      _publish(() {
        stateSectionErrors[section] =
            error is HikerCircleFirebaseRepositoryException
            ? error.message
            : 'This section could not load. Check your connection and retry.';
      });
    } finally {
      if (mounted && revision == stateAdminDataRevision) {
        _publish(() => stateLoadingSections.remove(section));
      }
    }
  }
}
