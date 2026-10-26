part of '../onboarding_profile_page_feature.dart';

/// Owns the state and non-visual actions of OnboardingProfilePage.
class _OnboardingProfilePageStateViewModel extends ChangeNotifier {
  /// Creates onboarding profile page state view model.
  _OnboardingProfilePageStateViewModel();

  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  /// Computes friendly error.
  String commandFriendlyError(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Password setup failed. Please try again.';
    }
    return error.toString();
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
