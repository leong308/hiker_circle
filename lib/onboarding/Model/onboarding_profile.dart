// OnboardingProfile holds the hiker details and preferences collected during first-time setup.
/// Represents onboarding profile.
class OnboardingProfile {
  /// Creates onboarding profile.
  const OnboardingProfile({
    this.username = '',
    this.gender = '',
    this.hikerExperience = '',
    this.hikeFrequency = '',
    this.residentialLocation = '',
    this.residentialLatitude,
    this.residentialLongitude,
    this.photoURL,
  });

  /// Creates onboarding profile from a cloud record.
  factory OnboardingProfile.fromFirestore(Map<String, dynamic>? data) {
    return OnboardingProfile(
      username: _stringFrom(data?['username']),
      gender: _stringFrom(data?['gender']),
      hikerExperience: _stringFrom(data?['hikerExperience']),
      hikeFrequency: _stringFrom(data?['hikeFrequency']),
      residentialLocation: _stringFrom(data?['residentialLocation']),
      residentialLatitude: _doubleFrom(data?['residentialLatitude']),
      residentialLongitude: _doubleFrom(data?['residentialLongitude']),
      photoURL: _stringFromOrNull(data?['photoURL']),
    );
  }

  final String username;
  final String gender;
  final String hikerExperience;
  final String hikeFrequency;
  final String residentialLocation;
  final double? residentialLatitude;
  final double? residentialLongitude;
  final String? photoURL;

  /// Returns a copy with the supplied fields changed.
  OnboardingProfile copyWith({
    String? username,
    String? gender,
    String? hikerExperience,
    String? hikeFrequency,
    String? residentialLocation,
    double? residentialLatitude,
    double? residentialLongitude,
    String? photoURL,
  }) {
    return OnboardingProfile(
      username: username ?? this.username,
      gender: gender ?? this.gender,
      hikerExperience: hikerExperience ?? this.hikerExperience,
      hikeFrequency: hikeFrequency ?? this.hikeFrequency,
      residentialLocation: residentialLocation ?? this.residentialLocation,
      residentialLatitude: residentialLatitude ?? this.residentialLatitude,
      residentialLongitude: residentialLongitude ?? this.residentialLongitude,
      photoURL: photoURL ?? this.photoURL,
    );
  }

  /// Returns is complete.
  bool get isComplete =>
      username.trim().isNotEmpty &&
      gender.trim().isNotEmpty &&
      hikerExperience.trim().isNotEmpty &&
      hikeFrequency.trim().isNotEmpty &&
      residentialLocation.trim().isNotEmpty &&
      residentialLatitude != null &&
      residentialLongitude != null;

  /// Serializes this value for cloud storage.
  Map<String, dynamic> toFirestore() {
    return {
      'username': username.trim(),
      'gender': gender,
      'hikerExperience': hikerExperience,
      'hikeFrequency': hikeFrequency,
      'residentialLocation': residentialLocation.trim(),
      'residentialLatitude': residentialLatitude,
      'residentialLongitude': residentialLongitude,
      if (photoURL != null) 'photoURL': photoURL,
    };
  }

  /// Computes string from.
  static String _stringFrom(Object? value) {
    return value is String ? value.trim() : '';
  }

  /// Computes string from or null.
  static String? _stringFromOrNull(Object? value) {
    return value is String ? value.trim() : null;
  }

  /// Computes double from.
  static double? _doubleFrom(Object? value) {
    return value is num ? value.toDouble() : null;
  }
}
