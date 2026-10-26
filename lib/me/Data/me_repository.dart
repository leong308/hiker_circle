// MeRepository derives the profile overview and initial account sections from AppSession.
import 'package:flutter/material.dart';

import '../../app/Model/app_session.dart';
import '../Model/me_models.dart';

/// Represents me repository.
class MeRepository {
  /// Creates me repository.
  const MeRepository();

  /// Loads profile.
  MeProfile loadProfile({required AppSession session}) {
    final username = session.username.trim();
    return MeProfile(
      displayName: username.isEmpty ? 'Trail Friend' : username,
      handle:
          '@${username.isEmpty ? _profileHandleForPhone(session.phoneNumber) : username}',
      phoneNumber: session.phoneNumber,
      status: 'Ready for the next hike',
      photoURL: session.photoURL,
    );
  }

  /// Loads stats.
  List<MeStat> loadStats() {
    return const [
      MeStat(label: 'Circles', value: '0'),
      MeStat(label: 'Buddies', value: '0'),
      MeStat(label: 'Trails', value: '0'),
    ];
  }

  /// Loads sections.
  List<MeSection> loadSections() {
    return const [
      MeSection(
        title: 'Circle',
        items: [
          MeActionItem(
            icon: Icons.history_rounded,
            title: 'Hike history',
            subtitle: 'Your completed routes and recorded hike details',
          ),
          MeActionItem(
            icon: Icons.forum_rounded,
            title: 'My posts',
            subtitle: 'Trail updates, stories, and photos',
          ),
          MeActionItem(
            icon: Icons.groups_2_rounded,
            title: 'My circles',
            subtitle: 'Groups and people you hike with',
          ),
          MeActionItem(
            icon: Icons.person_add_alt_1_rounded,
            title: 'My buddies',
            subtitle: 'Friends, invites, and requests',
          ),
        ],
      ),
      MeSection(
        title: 'Safety',
        items: [
          MeActionItem(
            icon: Icons.contact_phone_rounded,
            title: 'Emergency contacts',
            subtitle: 'People to notify when SOS is active',
          ),
          MeActionItem(
            icon: Icons.location_on_rounded,
            title: 'Location sharing',
            subtitle: 'Choose who can see your live trail status',
          ),
        ],
      ),
      MeSection(
        title: 'Settings',
        items: [
          MeActionItem(
            icon: Icons.feedback_outlined,
            title: 'Send feedback',
            subtitle: 'Report a problem or suggest an improvement',
          ),
          MeActionItem(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Circle activity and safety alerts',
          ),
          MeActionItem(
            icon: Icons.help_rounded,
            title: 'Help center',
            subtitle: 'Support, guides, and app information',
          ),
          MeActionItem(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy Policy',
            subtitle: 'How HikerCircle collects, uses, and protects data',
          ),
          MeActionItem(
            icon: Icons.info_outline_rounded,
            title: 'Disclaimer',
            subtitle: 'Map data, hazards, SOS and location sharing limits',
          ),
        ],
      ),
    ];
  }
}

/// Computes profile handle for phone.
String _profileHandleForPhone(String phoneNumber) {
  final digits = phoneNumber.replaceAll(RegExp('[^0-9]'), '');
  if (digits.length <= 4) {
    return 'hiker$digits';
  }
  return 'hiker${digits.substring(digits.length - 4)}';
}
