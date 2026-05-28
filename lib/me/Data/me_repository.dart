import 'package:flutter/material.dart';

import '../Model/me_models.dart';

class MeRepository {
  const MeRepository();

  MeProfile loadProfile({required String phoneNumber}) {
    return MeProfile(
      displayName: 'Trail Friend',
      handle: '@hikercircle',
      phoneNumber: phoneNumber,
      status: 'Ready for the next hike',
    );
  }

  List<MeStat> loadStats() {
    return const [
      MeStat(label: 'Circles', value: '6'),
      MeStat(label: 'Buddies', value: '24'),
      MeStat(label: 'Trails', value: '12'),
    ];
  }

  List<MeSection> loadSections() {
    return const [
      MeSection(
        title: 'Circle',
        items: [
          MeActionItem(
            icon: Icons.forum_rounded,
            title: 'My posts',
            subtitle: 'Trail updates, stories, and photos',
          ),
          MeActionItem(
            icon: Icons.groups_2_rounded,
            title: 'Hiking circles',
            subtitle: 'Groups and people you hike with',
          ),
          MeActionItem(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Trail buddies',
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
          MeActionItem(
            icon: Icons.medical_information_rounded,
            title: 'Medical notes',
            subtitle: 'Allergies, blood type, and key details',
          ),
        ],
      ),
      MeSection(
        title: 'Settings',
        items: [
          MeActionItem(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Circle activity and safety alerts',
          ),
          MeActionItem(
            icon: Icons.lock_rounded,
            title: 'Privacy',
            subtitle: 'Profile visibility and sharing controls',
          ),
          MeActionItem(
            icon: Icons.help_rounded,
            title: 'Help center',
            subtitle: 'Support, guides, and app information',
          ),
        ],
      ),
    ];
  }
}
