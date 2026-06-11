import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';
import '../../home/Model/hike_session_models.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';

class CirclePage extends StatefulWidget {
  const CirclePage({
    super.key,
    required this.session,
    required this.hikerCircleRepository,
    this.activeHike,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final ActiveHikeSession? activeHike;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<CirclePage> createState() => _CirclePageState();
}

class _CirclePageState extends State<CirclePage> {
  int _selectedSection = 0;
  late final EmergencyContactsRepository _contactsRepository;
  List<EmergencyContact> _contacts = const [];
  bool _isLoadingContacts = false;

  @override
  void initState() {
    super.initState();
    _contactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
    unawaited(_loadEmergencyContacts());
  }

  Future<void> _loadEmergencyContacts() async {
    setState(() {
      _isLoadingContacts = true;
    });
    try {
      final contacts = await _contactsRepository.loadEmergencyContacts(
        session: widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _contacts = contacts;
      });
    } catch (_) {
      // Keep the empty state visible when Firebase is unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingContacts = false;
        });
      }
    }
  }

  Future<void> _openEmergencyContacts() async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) => EmergencyContactsPage(
          session: widget.session,
          initialContacts: _contacts,
          repository: _contactsRepository,
        ),
      ),
    );

    if (contacts == null || !mounted) {
      return;
    }

    setState(() {
      _contacts = contacts;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _CircleColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),
                  const SizedBox(height: 16),
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: _selectedSection,
                    children: const {
                      0: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Contacts'),
                      ),
                      1: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Teams'),
                      ),
                      2: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Community'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSection = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey(_selectedSection),
                      child: switch (_selectedSection) {
                        0 => _ContactsSection(
                          contacts: _contacts,
                          isLoadingContacts: _isLoadingContacts,
                          onManageContacts: () =>
                              unawaited(_openEmergencyContacts()),
                        ),
                        1 => _TeamsSection(
                          session: widget.session,
                          hikerCircleRepository: widget.hikerCircleRepository,
                        ),
                        _ => _CommunitySection(
                          session: widget.session,
                          activeHike: widget.activeHike,
                          hikerCircleRepository: widget.hikerCircleRepository,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Circle',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: _CircleColors.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Contacts, team hikes, and safety community updates',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _CircleColors.secondaryText,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactsSection extends StatelessWidget {
  const _ContactsSection({
    required this.contacts,
    required this.isLoadingContacts,
    required this.onManageContacts,
  });

  final List<EmergencyContact> contacts;
  final bool isLoadingContacts;
  final VoidCallback onManageContacts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Safety Circle'),
        if (isLoadingContacts) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < contacts.length; index++) ...[
                _ContactCell(contact: contacts[index]),
                if (index != contacts.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
              if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(
                    child: Text('No saved emergency contacts in Firebase yet'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onManageContacts,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add Emergency Contact'),
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Local Assistance Numbers'),
        const SizedBox(height: 8),
        const _InsetGroup(
          child: Column(
            children: [
              _StatusRow(label: 'Malaysia Emergency Services', value: '999'),
              _HorizontalSeparator(),
              _StatusRow(label: 'Saved for Offline Access', value: 'Ready'),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(label: 'Location Sharing'),
        const SizedBox(height: 8),
        const _InsetGroup(
          child: Column(
            children: [
              _StatusRow(label: 'Share only during active hike', value: 'ON'),
              _HorizontalSeparator(),
              _StatusRow(
                label: 'Send overdue check-in notification',
                value: 'ON',
              ),
              _HorizontalSeparator(),
              _StatusRow(label: 'Send SOS alert automatically', value: 'ON'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactCell extends StatelessWidget {
  const _ContactCell({required this.contact});

  final EmergencyContact contact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          const _Glyph(icon: Icons.person_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _CircleColors.text,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${contact.relationship} - Receives SOS Alert',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _CircleColors.secondaryText,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const _StatusPill(label: 'Enabled', color: _CircleColors.green),
        ],
      ),
    );
  }
}

class _TeamsSection extends StatefulWidget {
  const _TeamsSection({
    required this.session,
    required this.hikerCircleRepository,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;

  @override
  State<_TeamsSection> createState() => _TeamsSectionState();
}

class _TeamsSectionState extends State<_TeamsSection> {
  bool _isCreatingTeam = false;
  bool _isLoadingTeams = false;
  List<Map<String, dynamic>> _teams = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadTeams());
  }

  Future<void> _loadTeams() async {
    setState(() {
      _isLoadingTeams = true;
    });
    try {
      final teams = await widget.hikerCircleRepository.loadTeamSchedules(
        session: widget.session,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _teams = teams;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTeams = false;
        });
      }
    }
  }

  Future<void> _createTeamSchedule() async {
    if (_isCreatingTeam) {
      return;
    }

    setState(() {
      _isCreatingTeam = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.hikerCircleRepository.createTeamSchedule(
        session: widget.session,
      );
      await _loadTeams();
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Team hike schedule created in Firebase.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to create team schedule: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingTeam = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'My Hiking Teams'),
        if (_isLoadingTeams) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        if (_teams.isEmpty)
          const _EmptyState(message: 'No Firebase team schedules yet.')
        else
          for (final team in _teams) ...[
            _TeamScheduleCard(team: team),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 10),
        _SectionTitle(label: 'Team Safety Logic'),
        const SizedBox(height: 8),
        const _InsetGroup(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Separation warnings compare member progress, stale updates, and route boundary status before escalation.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _isCreatingTeam
              ? null
              : () => unawaited(_createTeamSchedule()),
          icon: const Icon(Icons.add_rounded),
          label: Text(_isCreatingTeam ? 'Creating' : 'Create Hiking Team'),
        ),
      ],
    );
  }
}

class _CommunitySection extends StatefulWidget {
  const _CommunitySection({
    required this.session,
    required this.hikerCircleRepository,
    required this.activeHike,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository hikerCircleRepository;
  final ActiveHikeSession? activeHike;

  @override
  State<_CommunitySection> createState() => _CommunitySectionState();
}

class _CommunitySectionState extends State<_CommunitySection> {
  bool _isSharing = false;
  bool _isLoadingFeed = false;
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _hazards = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadFeed());
  }

  Future<void> _loadFeed() async {
    setState(() {
      _isLoadingFeed = true;
    });
    try {
      final posts = await widget.hikerCircleRepository.loadCommunityPosts();
      final hazards = await widget.hikerCircleRepository.loadHazardReports();
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = posts;
        _hazards = hazards;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFeed = false;
        });
      }
    }
  }

  Future<void> _shareCompletedHike() async {
    final activeHike = widget.activeHike;
    if (activeHike == null || _isSharing) {
      return;
    }

    setState(() {
      _isSharing = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.hikerCircleRepository.createCompletedHikePost(
        session: widget.session,
        activeHike: activeHike,
        caption: 'Shared from my active HikerCircle session.',
      );
      await _loadFeed();
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Completed hike post created in Firebase.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to share hike post: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShare = widget.activeHike != null && !_isSharing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(label: 'Community'),
        if (_isLoadingFeed) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: const [
              ChoiceChip(label: Text('Following'), selected: true),
              SizedBox(width: 8),
              ChoiceChip(label: Text('Nearby Trails'), selected: false),
              SizedBox(width: 8),
              ChoiceChip(label: Text('Hazards'), selected: false),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canShare ? () => unawaited(_shareCompletedHike()) : null,
          icon: const Icon(Icons.add_photo_alternate_rounded),
          label: Text(
            widget.activeHike == null
                ? 'Complete a Hike to Share'
                : _isSharing
                ? 'Sharing'
                : 'Share Completed Hike',
          ),
        ),
        const SizedBox(height: 14),
        if (_posts.isEmpty)
          const _EmptyState(message: 'No Firebase community posts yet.')
        else
          for (final post in _posts) ...[
            _CommunityPostCard(post: post),
            const SizedBox(height: 12),
          ],
        if (_hazards.isEmpty)
          const _EmptyState(message: 'No Firebase hazard reports yet.')
        else
          for (final hazard in _hazards) ...[
            _HazardFeedCard(hazard: hazard),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _TeamScheduleCard extends StatelessWidget {
  const _TeamScheduleCard({required this.team});

  final Map<String, dynamic> team;

  @override
  Widget build(BuildContext context) {
    final members = team['memberIds'] is Iterable
        ? (team['memberIds'] as Iterable).length
        : 0;

    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.event_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stringFrom(team['teamName'], fallback: 'Team Hike'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _CircleColors.text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        _stringFrom(team['status'], fallback: 'planned'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _CircleColors.secondaryText,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: 'Trail',
              value: _stringFrom(team['trailName'], fallback: 'Not selected'),
            ),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Planned',
              value: _stringFrom(
                team['plannedStartTimeLocal'],
                fallback: 'No date',
              ),
            ),
            const _HorizontalSeparator(),
            _StatusRow(label: 'Members', value: '$members Members'),
          ],
        ),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  const _CommunityPostCard({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _Glyph(icon: Icons.hiking_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_stringFrom(post['authorPhoneNumber'], fallback: 'Hiker')} completed ${_stringFrom(post['trailName'], fallback: 'a trail')}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: _CircleColors.text,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                      ),
                      Text(
                        _stringFrom(
                          post['createdAtLocal'],
                          fallback: 'Just now',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _CircleColors.secondaryText,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: const _CommunityImagePainter(),
                child: const SizedBox(height: 150, width: double.infinity),
              ),
            ),
            const SizedBox(height: 12),
            _StatusRow(
              label: 'Distance',
              value: '${_numberFrom(post['distanceKm']).toStringAsFixed(1)} km',
            ),
            const _HorizontalSeparator(),
            _StatusRow(
              label: 'Duration',
              value: '${_numberFrom(post['durationMinutes']).round()} min',
            ),
            const SizedBox(height: 10),
            Text(
              '"${_stringFrom(post['caption'], fallback: 'Shared a completed hike.')}"',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _CircleColors.text,
                fontStyle: FontStyle.italic,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_numberFrom(post['likeCount']).round()} Likes - ${_numberFrom(post['commentCount']).round()} Comments',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _CircleColors.secondaryText,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardFeedCard extends StatelessWidget {
  const _HazardFeedCard({required this.hazard});

  final Map<String, dynamic> hazard;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Glyph(
              icon: Icons.warning_amber_rounded,
              color: _CircleColors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hazard Report - ${_stringFrom(hazard['trailName'], fallback: 'Trail')}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _CircleColors.text,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _stringFrom(
                      hazard['description'],
                      fallback: 'Community hazard report',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _CircleColors.text,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Community Report - Not Officially Verified',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _CircleColors.orange,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('View on Map'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _CircleColors.text,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _CircleColors.secondaryText,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _CircleColors.secondaryText,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _CircleColors.secondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, this.color = _CircleColors.green});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    );
  }
}

class _HorizontalSeparator extends StatelessWidget {
  const _HorizontalSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.7,
      color: _CircleColors.separator,
    );
  }
}

class _CommunityImagePainter extends CustomPainter {
  const _CommunityImagePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()..color = const Color(0xFF6EA7C8);
    final hillBack = Paint()..color = const Color(0xFF7E9B6D);
    final hillFront = Paint()..color = const Color(0xFF426B48);
    canvas.drawRect(Offset.zero & size, sky);

    final back = Path()
      ..moveTo(0, size.height * 0.74)
      ..lineTo(size.width * 0.22, size.height * 0.38)
      ..lineTo(size.width * 0.45, size.height * 0.70)
      ..lineTo(size.width * 0.70, size.height * 0.34)
      ..lineTo(size.width, size.height * 0.70)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(back, hillBack);

    final front = Path()
      ..moveTo(0, size.height * 0.86)
      ..lineTo(size.width * 0.30, size.height * 0.56)
      ..lineTo(size.width * 0.58, size.height * 0.80)
      ..lineTo(size.width * 0.84, size.height * 0.52)
      ..lineTo(size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, hillFront);
  }

  @override
  bool shouldRepaint(covariant _CommunityImagePainter oldDelegate) {
    return false;
  }
}

String _stringFrom(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return fallback;
}

double _numberFrom(Object? value) {
  return value is num ? value.toDouble() : 0;
}

abstract final class _CircleColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color orange = Color(0xFFF59E0B);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
}
