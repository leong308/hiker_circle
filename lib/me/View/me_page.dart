import 'dart:async';
import 'dart:convert';

import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/app_settings_controller.dart';
import '../../app/Data/firebase_bootstrap.dart';
import '../../app/Data/local_session_database.dart';
import '../../app/Model/app_session.dart';
import '../../sos/Data/emergency_contacts_repository.dart';
import '../../sos/Data/sos_device_alert_service.dart';
import '../../sos/Model/sos_models.dart';
import '../../sos/View/emergency_contacts_page.dart';
import '../Model/me_models.dart';
import '../ModelView/me_view_model.dart';
import 'location_sharing_page.dart';

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    required this.session,
    required this.phoneNumber,
    required this.onSignOut,
    this.firebaseBootstrapResult = const FirebaseBootstrapResult.available(),
  });

  final AppSession session;
  final String phoneNumber;
  final VoidCallback onSignOut;
  final FirebaseBootstrapResult firebaseBootstrapResult;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final MeViewModel viewModel;
  late final EmergencyContactsRepository emergencyContactsRepository;
  List<EmergencyContact> emergencyContacts = const [
    EmergencyContact(
      name: 'Mother',
      phoneNumber: '+60123456789',
      relationship: 'Family',
    ),
    EmergencyContact(
      name: 'Brother',
      phoneNumber: '+60198765432',
      relationship: 'Family',
    ),
  ];

  @override
  void initState() {
    super.initState();
    viewModel = MeViewModel(phoneNumber: widget.phoneNumber);
    emergencyContactsRepository = EmergencyContactsRepository(
      firebaseBootstrapResult: widget.firebaseBootstrapResult,
    );
  }

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _MeColors.backgroundFor(context),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    profile: viewModel.profile,
                    onShowQr: _openQrCode,
                    onOpenScanner: _openQrScanner,
                    onOpenSettings: _openAdvancedSettings,
                  ),
                  const SizedBox(height: 16),
                  _ProfileCell(profile: viewModel.profile, onTap: _openQrCode),
                  const SizedBox(height: 14),
                  _StatsGroup(
                    stats: _linkedProfileStats,
                    onTap: _openStatDetail,
                  ),
                  const SizedBox(height: 22),
                  for (final section in viewModel.sections) ...[
                    _SettingsSection(
                      section: section,
                      onItemTap: _openActionItem,
                    ),
                    const SizedBox(height: 18),
                  ],
                  _SignOutCell(onSignOut: widget.onSignOut),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openActionItem(MeActionItem item) {
    switch (item.title) {
      case 'My posts':
        _openHistoryPage(
          title: 'My Posts',
          subtitle: 'Trail updates from your hiking history',
          icon: Icons.forum_rounded,
          items: _postHistoryItems,
        );
      case 'Hiking circles':
        _openHistoryPage(
          title: 'Hiking Circles',
          subtitle: 'Each circle represents a hiking team',
          icon: Icons.groups_2_rounded,
          items: _circleHistoryItems,
        );
      case 'Trail buddies':
        _openHistoryPage(
          title: 'Trail Buddies',
          subtitle: 'People from past hikes and QR adds',
          icon: Icons.person_add_alt_1_rounded,
          items: _buddyHistoryItems,
        );
      case 'Emergency contacts':
        _openEmergencyContacts();
      case 'Location sharing':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => LocationSharingPage(
              phoneNumber: widget.phoneNumber,
              firebaseBootstrapResult: widget.firebaseBootstrapResult,
            ),
          ),
        );
      case 'Safety preferences':
        _openSettingsDetail(
          title: 'Safety Preferences',
          subtitle: 'Trail safety defaults',
          icon: Icons.rule_rounded,
          rows: const [
            ('Check-in reminder', 'Every 30 minutes during active hikes'),
            ('Overdue escalation', 'Warn buddies after 15 minutes'),
            ('Trail visibility', 'Buddies only while hiking'),
            ('Fallback alert', 'Use local SOS if network is unavailable'),
          ],
        );
      case 'Notifications':
        _openSettingsDetail(
          title: 'Notifications',
          subtitle: 'Community and safety alerts',
          icon: Icons.notifications_rounded,
          rows: const [
            ('SOS delivery updates', 'On'),
            ('Buddy requests', 'On'),
            ('Team invite changes', 'On'),
            ('Nearby hazard reports', 'Priority only'),
            ('Quiet hours', '11:00 PM - 6:00 AM'),
          ],
        );
      case 'Privacy':
        _openSettingsDetail(
          title: 'Privacy',
          subtitle: 'Profile visibility and sharing',
          icon: Icons.lock_rounded,
          rows: const [
            ('Profile visibility', 'Buddies and team members'),
            ('Hike history', 'Show completed public hikes'),
            ('Live location', 'Only during active hike'),
            ('QR discovery', 'Ask before adding as buddy'),
          ],
        );
      case 'Help center':
        _openHelpCenter();
      case 'Account preferences':
        _openSettingsDetail(
          title: 'Account Preferences',
          subtitle: 'Profile and sign-in controls',
          icon: Icons.account_circle_rounded,
          rows: const [
            ('Display name', 'Trail Friend'),
            ('Phone sign-in', 'Verified'),
            ('Profile QR', 'Enabled'),
            ('Account recovery', 'Phone number'),
          ],
        );
      case 'Export history':
        _openSettingsDetail(
          title: 'Export History',
          subtitle: 'Downloadable activity records',
          icon: Icons.download_rounded,
          rows: _exportHistoryRows,
        );
    }
  }

  Future<void> _openEmergencyContacts() async {
    final contacts = await Navigator.of(context).push<List<EmergencyContact>>(
      MaterialPageRoute<List<EmergencyContact>>(
        builder: (context) => EmergencyContactsPage(
          session: widget.session,
          initialContacts: emergencyContacts,
          repository: emergencyContactsRepository,
        ),
      ),
    );

    if (contacts == null || !mounted) {
      return;
    }

    setState(() {
      emergencyContacts = contacts;
    });
  }

  void _openStatDetail(MeStat stat) {
    switch (stat.label) {
      case 'Circles':
        _openHistoryPage(
          title: 'Hiking Circles',
          subtitle: 'Teams you created, joined, or completed',
          icon: Icons.groups_2_rounded,
          items: _circleHistoryItems,
        );
      case 'Buddies':
        _openHistoryPage(
          title: 'Trail Buddies',
          subtitle: 'Friends from hikes, community, and QR scans',
          icon: Icons.person_add_alt_1_rounded,
          items: _buddyHistoryItems,
        );
      case 'Trails':
        _openHistoryPage(
          title: 'Trail History',
          subtitle: 'Saved and completed routes',
          icon: Icons.map_rounded,
          items: _trailHistoryItems,
        );
    }
  }

  void _openHistoryPage({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_ProfileHistoryItem> items,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileHistoryPage(
          title: title,
          subtitle: subtitle,
          icon: icon,
          items: items,
        ),
      ),
    );
  }

  void _openSettingsDetail({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<(String, String)> rows,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileSettingsDetailPage(
          title: title,
          subtitle: subtitle,
          icon: icon,
          rows: rows,
        ),
      ),
    );
  }

  void _openHelpCenter() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const _HelpCenterPage()),
    );
  }

  void _openAdvancedSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _AdvancedAppSettingsPage(),
      ),
    );
  }

  void _openQrCode() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ProfileQrPage(profile: viewModel.profile),
      ),
    );
  }

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _QrScannerPlaceholderPage(),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.onShowQr,
    required this.onOpenScanner,
    required this.onOpenSettings,
  });

  final MeProfile profile;
  final VoidCallback onShowQr;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: _MeColors.textFor(context),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Welcome back, ${profile.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _MeColors.secondaryTextFor(context),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          _HeaderAction(
            tooltip: 'QR code',
            icon: Icons.qr_code_rounded,
            onPressed: onShowQr,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Scan QR',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: onOpenScanner,
          ),
          const SizedBox(width: 8),
          _HeaderAction(
            tooltip: 'Settings',
            icon: CupertinoIcons.gear_alt_fill,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        onPressed: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _MeColors.surfaceFor(context),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: _MeColors.green, size: 19),
        ),
      ),
    );
  }
}

class _ProfileCell extends StatelessWidget {
  const _ProfileCell({required this.profile, required this.onTap});

  final MeProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _MeColors.greenSoftFor(context),
                ),
                child: const Icon(
                  CupertinoIcons.person_fill,
                  color: _MeColors.green,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _MeColors.textFor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.qr_code_rounded,
                color: _MeColors.green,
                size: 22,
              ),
              const SizedBox(width: 12),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _MeColors.chevronFor(context),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileQrPage extends StatelessWidget {
  const _ProfileQrPage({required this.profile});

  final MeProfile profile;

  @override
  Widget build(BuildContext context) {
    final link = _profileLink(profile);
    final qr = _QrMatrix.encode(link);

    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Profile QR',
                    subtitle: 'Share your HikerCircle profile',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _MeColors.separatorFor(context),
                              ),
                            ),
                            child: CustomPaint(
                              painter: _QrPainter(matrix: qr.modules),
                              child: const SizedBox.square(dimension: 236),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            profile.displayName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _MeColors.textFor(context),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            link,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: _MeColors.secondaryTextFor(context),
                                  letterSpacing: 0,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _shareProfileLink(context, link),
                                  icon: const Icon(Icons.ios_share_rounded),
                                  label: const Text('Share Link'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _copyProfileLink(context, link),
                                  icon: const Icon(Icons.copy_rounded),
                                  label: const Text('Copy'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _InsetGroup(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Glyph(icon: Icons.link_rounded),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Scanning this QR opens HikerCircle through a deeplink. If another hiker scans it, the app shows an add-buddy prompt; your own QR is ignored.',
                            ),
                          ),
                        ],
                      ),
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

  void _copyProfileLink(BuildContext context, String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Profile link copied for sharing.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _shareProfileLink(BuildContext context, String link) async {
    try {
      await const MethodChannel('hiker_circle/sos_device_alerts').invokeMethod(
        'shareText',
        {'subject': 'Add me on HikerCircle', 'text': link},
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _copyProfileLink(context, link);
    }
  }
}

class _QrScannerPlaceholderPage extends StatelessWidget {
  const _QrScannerPlaceholderPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Scan QR',
                    subtitle: 'Profile scanner placeholder',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _InsetGroup(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _MeColors.green,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: _MeColors.green,
                                size: 72,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Camera scanner UI',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: _MeColors.textFor(context),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'UI-only for now. A camera plugin can read HikerCircle profile links and route them into the app later.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: _MeColors.secondaryTextFor(context),
                                    letterSpacing: 0,
                                  ),
                            ),
                          ],
                        ),
                      ),
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

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'Back',
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(36),
            onPressed: onBack,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _MeColors.surfaceFor(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.chevron_back,
                color: _MeColors.green,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _MeColors.textFor(context),
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _MeColors.secondaryTextFor(context),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.matrix});

  final List<List<bool>> matrix;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = matrix.length;
    final quietZone = 4;
    final cell = size.shortestSide / (modules + quietZone * 2);
    final offset = Offset(
      (size.width - cell * (modules + quietZone * 2)) / 2,
      (size.height - cell * (modules + quietZone * 2)) / 2,
    );
    final paint = Paint()..color = _MeColors.text;

    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (!matrix[y][x]) {
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              offset.dx + (x + quietZone) * cell,
              offset.dy + (y + quietZone) * cell,
              cell,
              cell,
            ),
            Radius.circular(cell * 0.12),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) {
    return oldDelegate.matrix != matrix;
  }
}

class _QrMatrix {
  _QrMatrix._(this.modules);

  static const int _version = 4;
  static const int _size = 17 + _version * 4;
  static const int _dataCodewords = 80;
  static const int _ecCodewords = 20;
  static const int _formatBitsLowMaskZero = 0x77C4;

  final List<List<bool>> modules;

  static _QrMatrix encode(String text) {
    final data = _buildDataCodewords(text);
    final errorCorrection = _computeRemainder(
      data,
      _computeDivisor(_ecCodewords),
    );
    final codewords = [...data, ...errorCorrection];
    final qr = _MutableQr();
    qr.drawFunctionPatterns();
    qr.drawCodewords(codewords);
    qr.applyMask();
    qr.drawFormatBits(_formatBitsLowMaskZero);
    return _QrMatrix._(qr.modules);
  }

  static List<int> _buildDataCodewords(String text) {
    final bytes = utf8.encode(text);
    if (bytes.length > 73) {
      throw ArgumentError('Profile link is too long for the local QR encoder.');
    }

    final bits = <bool>[];
    _appendBits(bits, 0x4, 4);
    _appendBits(bits, bytes.length, 8);
    for (final byte in bytes) {
      _appendBits(bits, byte, 8);
    }

    final capacityBits = _dataCodewords * 8;
    final terminator = (capacityBits - bits.length).clamp(0, 4);
    _appendBits(bits, 0, terminator);
    while (bits.length % 8 != 0) {
      bits.add(false);
    }

    final result = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var value = 0;
      for (var j = 0; j < 8; j++) {
        value = (value << 1) | (bits[i + j] ? 1 : 0);
      }
      result.add(value);
    }

    var pad = 0xEC;
    while (result.length < _dataCodewords) {
      result.add(pad);
      pad ^= 0xEC ^ 0x11;
    }
    return result;
  }

  static void _appendBits(List<bool> bits, int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add(((value >> i) & 1) != 0);
    }
  }

  static List<int> _computeDivisor(int degree) {
    final result = List<int>.filled(degree, 0);
    result[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < result.length; j++) {
        result[j] = _multiply(result[j], root);
        if (j + 1 < result.length) {
          result[j] ^= result[j + 1];
        }
      }
      root = _multiply(root, 0x02);
    }
    return result;
  }

  static List<int> _computeRemainder(List<int> data, List<int> divisor) {
    final result = List<int>.filled(divisor.length, 0, growable: true);
    for (final byte in data) {
      final factor = byte ^ result.removeAt(0);
      result.add(0);
      for (var i = 0; i < result.length; i++) {
        result[i] ^= _multiply(divisor[i], factor);
      }
    }
    return result;
  }

  static int _multiply(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      if (((y >> i) & 1) != 0) {
        z ^= x;
      }
    }
    return z & 0xFF;
  }
}

class _MutableQr {
  final List<List<bool>> modules = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );
  final List<List<bool>> _isFunction = List.generate(
    _QrMatrix._size,
    (_) => List<bool>.filled(_QrMatrix._size, false),
  );

  void drawFunctionPatterns() {
    _drawFinder(3, 3);
    _drawFinder(_QrMatrix._size - 4, 3);
    _drawFinder(3, _QrMatrix._size - 4);

    for (var i = 0; i < _QrMatrix._size; i++) {
      if (!_isFunction[6][i]) {
        _setFunction(i, 6, i.isEven);
      }
      if (!_isFunction[i][6]) {
        _setFunction(6, i, i.isEven);
      }
    }

    _drawAlignment(26, 26);
    _setFunction(8, 4 * _QrMatrix._version + 9, true);
    drawFormatBits(0);
  }

  void _drawFinder(int centerX, int centerY) {
    for (var dy = -4; dy <= 4; dy++) {
      for (var dx = -4; dx <= 4; dx++) {
        final x = centerX + dx;
        final y = centerY + dy;
        if (x < 0 || x >= _QrMatrix._size || y < 0 || y >= _QrMatrix._size) {
          continue;
        }
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(x, y, distance != 2 && distance != 4);
      }
    }
  }

  void _drawAlignment(int centerX, int centerY) {
    for (var dy = -2; dy <= 2; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        final distance = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
        _setFunction(centerX + dx, centerY + dy, distance != 1);
      }
    }
  }

  void drawFormatBits(int bits) {
    for (var i = 0; i <= 5; i++) {
      _setFunction(8, i, _bit(bits, i));
    }
    _setFunction(8, 7, _bit(bits, 6));
    _setFunction(8, 8, _bit(bits, 7));
    _setFunction(7, 8, _bit(bits, 8));
    for (var i = 9; i < 15; i++) {
      _setFunction(14 - i, 8, _bit(bits, i));
    }
    for (var i = 0; i < 8; i++) {
      _setFunction(_QrMatrix._size - 1 - i, 8, _bit(bits, i));
    }
    for (var i = 8; i < 15; i++) {
      _setFunction(8, _QrMatrix._size - 15 + i, _bit(bits, i));
    }
  }

  void drawCodewords(List<int> codewords) {
    final bits = <bool>[];
    for (final codeword in codewords) {
      for (var i = 7; i >= 0; i--) {
        bits.add(((codeword >> i) & 1) != 0);
      }
    }

    var bitIndex = 0;
    var upward = true;
    for (var right = _QrMatrix._size - 1; right >= 1; right -= 2) {
      if (right == 6) {
        right = 5;
      }
      for (var vert = 0; vert < _QrMatrix._size; vert++) {
        final y = upward ? _QrMatrix._size - 1 - vert : vert;
        for (var dx = 0; dx < 2; dx++) {
          final x = right - dx;
          if (_isFunction[y][x]) {
            continue;
          }
          modules[y][x] = bitIndex < bits.length && bits[bitIndex];
          bitIndex++;
        }
      }
      upward = !upward;
    }
  }

  void applyMask() {
    for (var y = 0; y < _QrMatrix._size; y++) {
      for (var x = 0; x < _QrMatrix._size; x++) {
        if (!_isFunction[y][x] && (x + y).isEven) {
          modules[y][x] = !modules[y][x];
        }
      }
    }
  }

  void _setFunction(int x, int y, bool isDark) {
    modules[y][x] = isDark;
    _isFunction[y][x] = true;
  }

  static bool _bit(int value, int index) {
    return ((value >> index) & 1) != 0;
  }
}

String _profileLink(MeProfile profile) {
  final handle = Uri.encodeComponent(profile.handle.replaceFirst('@', ''));
  final name = Uri.encodeComponent(profile.displayName);
  return 'hikercircle://buddy/add?h=$handle&n=$name';
}

List<MeStat> get _linkedProfileStats {
  return [
    MeStat(label: 'Circles', value: '${_circleHistoryItems.length}'),
    MeStat(label: 'Buddies', value: '${_buddyHistoryItems.length}'),
    MeStat(label: 'Trails', value: '${_trailHistoryItems.length}'),
  ];
}

List<(String, String)> get _exportHistoryRows {
  return [
    ('Hikes', '${_trailHistoryItems.length} completed trails'),
    ('Posts', '${_postHistoryItems.length} community updates'),
    ('Circles', '${_circleHistoryItems.length} hiking teams'),
    ('Buddies', '${_buddyHistoryItems.length} trail buddies'),
    ('Format', 'CSV and JSON dummy preview'),
  ];
}

String? _countLabelForAction(String title) {
  return switch (title) {
    'My posts' => '${_postHistoryItems.length}',
    'Hiking circles' => '${_circleHistoryItems.length}',
    'Trail buddies' => '${_buddyHistoryItems.length}',
    'Export history' =>
      '${_postHistoryItems.length + _circleHistoryItems.length + _buddyHistoryItems.length + _trailHistoryItems.length}',
    _ => null,
  };
}

const List<_ProfileHistoryItem> _postHistoryItems = [
  _ProfileHistoryItem(
    title: 'Broga sunrise note',
    subtitle: 'Shared muddy fork warning and sunrise timing after a hike.',
    meta: '42 likes - 8 replies',
    icon: Icons.forum_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Gasing easy loop recap',
    subtitle: 'Posted a beginner-friendly route recap with checkpoint advice.',
    meta: '18 likes - 3 replies',
    icon: Icons.photo_library_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Rain gear reminder',
    subtitle: 'Community tip from a wet Penang Hill morning session.',
    meta: 'Saved by 9 hikers',
    icon: Icons.umbrella_rounded,
  ),
];

const List<_ProfileHistoryItem> _circleHistoryItems = [
  _ProfileHistoryItem(
    title: 'Gasing Easy Loop',
    subtitle: 'Team circle with Aina, Jason, and Farid.',
    meta: '4 members - Ready',
    icon: Icons.groups_2_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Morning Ridge Crew',
    subtitle: 'Broga Hill team draft from QR-added buddies.',
    meta: '5 members - Draft',
    icon: Icons.flag_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Penang Mist Walk',
    subtitle: 'Completed circle from a heritage trail hike.',
    meta: '3 members - Completed',
    icon: Icons.verified_rounded,
  ),
];

const List<_ProfileHistoryItem> _buddyHistoryItems = [
  _ProfileHistoryItem(
    title: 'Aina',
    subtitle: 'Added from Community after Broga Hill safety notes.',
    meta: '@ainatrails',
    icon: Icons.person_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Jason',
    subtitle: 'Joined two team hikes and leads beginner loops.',
    meta: '@jasonridge',
    icon: Icons.person_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Mei Lin',
    subtitle: 'Added from a QR scan after Tabur route planning.',
    meta: '@meiclimbs',
    icon: Icons.qr_code_rounded,
  ),
];

const List<_ProfileHistoryItem> _trailHistoryItems = [
  _ProfileHistoryItem(
    title: 'Broga Hill Trail',
    subtitle: 'Completed sunrise hike with one hazard report reviewed.',
    meta: '3.4 km - Moderate',
    icon: Icons.terrain_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Bukit Gasing Trail',
    subtitle: 'Saved offline and used for team training.',
    meta: '5.1 km - Easy',
    icon: Icons.map_rounded,
  ),
  _ProfileHistoryItem(
    title: 'Penang Hill Heritage Trail',
    subtitle: 'Completed in misty weather with team check-ins.',
    meta: '4.8 km - Moderate',
    icon: Icons.landscape_rounded,
  ),
];

class _ProfileHistoryItem {
  const _ProfileHistoryItem({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
}

class _ProfileHistoryPage extends StatelessWidget {
  const _ProfileHistoryPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_ProfileHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: title,
                    subtitle: subtitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _Glyph(icon: icon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${items.length} history item${items.length == 1 ? '' : 's'} from dummy profile activity.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: _MeColors.textFor(context),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final item in items) ...[
                    _ProfileHistoryCard(item: item),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHistoryCard extends StatelessWidget {
  const _ProfileHistoryCard({required this.item});

  final _ProfileHistoryItem item;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${item.title} detail opened.'),
              behavior: SnackBarBehavior.floating,
            ),
          ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Glyph(icon: item.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _MeColors.textFor(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _MeColors.secondaryTextFor(context),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MiniPill(label: item.meta),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                color: _MeColors.chevronFor(context),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSettingsDetailPage extends StatelessWidget {
  const _ProfileSettingsDetailPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rows,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: title,
                    subtitle: subtitle,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _InsetGroup(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _Glyph(icon: icon),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Configured for HikerCircle profile behavior.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: _MeColors.textFor(context),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0,
                                      ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (var index = 0; index < rows.length; index++) ...[
                            _InfoLine(
                              label: rows[index].$1,
                              value: rows[index].$2,
                            ),
                            if (index != rows.length - 1)
                              const _HorizontalSeparator(),
                          ],
                        ],
                      ),
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

class _HelpCenterPage extends StatelessWidget {
  const _HelpCenterPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'Help Center',
                    subtitle: 'Guides, support, and safety education',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  const _ProfileHistoryCard(
                    item: _ProfileHistoryItem(
                      title: 'Using SOS safely',
                      subtitle:
                          'Understand manual SOS, local SOS, and duress behavior.',
                      meta: 'Safety guide',
                      icon: Icons.sos_rounded,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _ProfileHistoryCard(
                    item: _ProfileHistoryItem(
                      title: 'Team hike basics',
                      subtitle:
                          'How circles, buddies, check-ins, and roles work together.',
                      meta: 'Team guide',
                      icon: Icons.groups_2_rounded,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _ProfileHistoryCard(
                    item: _ProfileHistoryItem(
                      title: 'Report a problem',
                      subtitle:
                          'Dummy support entry for account, map, or community issues.',
                      meta: 'Support',
                      icon: Icons.support_agent_rounded,
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

class _AdvancedAppSettingsPage extends StatefulWidget {
  const _AdvancedAppSettingsPage();

  @override
  State<_AdvancedAppSettingsPage> createState() =>
      _AdvancedAppSettingsPageState();
}

class _AdvancedAppSettingsPageState extends State<_AdvancedAppSettingsPage> {
  final AppSettingsController _settings = AppSettingsController.instance;
  final LocalSessionDatabase _localDatabase = LocalSessionDatabase();
  final SosDeviceAlertService _deviceAlertService =
      const SosDeviceAlertService();
  String _language = 'English';
  CacheUsageSummary? _cacheUsageSummary;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_handleSettingsChanged);
    unawaited(_loadCacheUsage());
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCacheUsage() async {
    final summary = await _localDatabase.loadCacheUsageSummary();
    if (!mounted) {
      return;
    }
    setState(() {
      _cacheUsageSummary = summary;
    });
  }

  Future<void> _setPreciseLocation(bool enabled) async {
    if (!enabled) {
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) {
          return CupertinoAlertDialog(
            title: const Text('Reduce Location Accuracy?'),
            content: const Text(
              'Turning off precise location can improve battery life, but hike tracking, pins, and SOS map links may be less accurate.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Precise'),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn Off'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
    }

    _settings.setPreciseLocationEnabled(enabled);
    await _deviceAlertService.setPreciseLocationEnabled(enabled);
  }

  Future<void> _clearCacheData() async {
    if (_isClearingCache) {
      return;
    }
    setState(() {
      _isClearingCache = true;
    });
    await _localDatabase.clearCacheData();
    await _loadCacheUsage();
    if (!mounted) {
      return;
    }
    setState(() {
      _isClearingCache = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Map cache and network samples cleared.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _MeColors.backgroundFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailHeader(
                    title: 'App Settings',
                    subtitle: 'Advanced preferences and device controls',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: 'Language'),
                  const SizedBox(height: 8),
                  _ChoiceSettingCard(
                    icon: Icons.language_rounded,
                    title: 'App language',
                    value: _language,
                    options: const ['English', 'Malay', 'Chinese'],
                    onSelected: (value) => setState(() => _language = value),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Appearance & Theme'),
                  const SizedBox(height: 8),
                  _ChoiceSettingCard(
                    icon: Icons.palette_rounded,
                    title: 'Theme mode',
                    value: _settings.themeSetting.label,
                    options: HikerCircleThemeSetting.values
                        .map((setting) => setting.label)
                        .toList(),
                    onSelected: (value) => _settings.setThemeSetting(
                      HikerCircleThemeSetting.fromLabel(value),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Permissions'),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.location_on_rounded,
                    title: 'Precise location for hikes and SOS',
                    subtitle:
                        'Used for route tracking and emergency map links.',
                    value: _settings.preciseLocationEnabled,
                    onChanged: (value) => unawaited(_setPreciseLocation(value)),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Storage & Cache'),
                  const SizedBox(height: 8),
                  _CacheUsageCard(
                    icon: Icons.storage_rounded,
                    title: 'Cache usage',
                    subtitle:
                        _cacheUsageSummary?.label ?? 'Calculating cache usage',
                    isClearing: _isClearingCache,
                    onClear: () => unawaited(_clearCacheData()),
                  ),
                  const SizedBox(height: 18),
                  _SectionTitle(label: 'Trail Recommendations'),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.insights_rounded,
                    title:
                        'Allow HikerCircle to collect and use my trail data as anonymous',
                    subtitle:
                        'Allows HikerCircle to use your trail pathway anonymously as recommendations for other hikers and reduce map-based outliers.',
                    value: _settings.anonymousTrailRecommendationsEnabled,
                    onChanged:
                        _settings.setAnonymousTrailRecommendationsEnabled,
                  ),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.vibration_rounded,
                    title: 'Haptic safety feedback',
                    subtitle:
                        'Use short vibrations for check-ins, pins, and SOS countdown actions.',
                    value: _settings.hapticSafetyFeedbackEnabled,
                    onChanged: _settings.setHapticSafetyFeedbackEnabled,
                  ),
                  const SizedBox(height: 8),
                  _SwitchSettingCard(
                    icon: Icons.battery_alert_rounded,
                    title: 'Low battery safety warnings',
                    subtitle:
                        'Warn before a hike when battery may be too low for safe tracking.',
                    value: _settings.lowBatterySafetyWarningEnabled,
                    onChanged: _settings.setLowBatterySafetyWarningEnabled,
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

class _StatsGroup extends StatelessWidget {
  const _StatsGroup({required this.stats, required this.onTap});

  final List<MeStat> stats;
  final ValueChanged<MeStat> onTap;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var index = 0; index < stats.length; index++) ...[
              Expanded(
                child: _StatCell(
                  stat: stats[index],
                  onTap: () => onTap(stats[index]),
                ),
              ),
              if (index != stats.length - 1) const _VerticalSeparator(),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChoiceSettingCard extends StatelessWidget {
  const _ChoiceSettingCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

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
                _Glyph(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _MiniPill(label: value),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option),
                    selected: value == option,
                    onSelected: (_) => onSelected(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchSettingCard extends StatelessWidget {
  const _SwitchSettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _AnimatedBooleanToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _AnimatedBooleanToggle extends StatelessWidget {
  const _AnimatedBooleanToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedToggleSwitch<bool>.size(
      current: value,
      values: const [false, true],
      height: 38,
      spacing: 2,
      indicatorSize: const Size.square(32),
      borderWidth: 2,
      style: ToggleStyle(
        backgroundColor: _MeColors.greenSoftFor(context),
        borderColor: _MeColors.separatorFor(context),
        borderRadius: BorderRadius.circular(999),
        indicatorBorderRadius: BorderRadius.circular(999),
      ),
      styleBuilder: (enabled) => ToggleStyle(
        indicatorColor: enabled
            ? _MeColors.green
            : _MeColors.destructiveFor(context),
      ),
      iconBuilder: (enabled) => Icon(
        enabled ? Icons.check_rounded : Icons.close_rounded,
        color: enabled ? _MeColors.green : _MeColors.destructiveFor(context),
        size: 17,
      ),
      foregroundIndicatorIconBuilder: (context, global) {
        final enabled = global.current;
        return Icon(
          enabled ? Icons.check_rounded : Icons.close_rounded,
          color: _MeColors.surfaceFor(context),
          size: 18,
        );
      },
      iconOpacity: 0.72,
      selectedIconOpacity: 0,
      selectedIconScale: 1,
      animationDuration: const Duration(milliseconds: 260),
      animationCurve: Curves.easeOutCubic,
      onChanged: onChanged,
    );
  }
}

class _CacheUsageCard extends StatelessWidget {
  const _CacheUsageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isClearing,
    required this.onClear,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isClearing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glyph(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: isClearing ? null : onClear,
                      icon: isClearing
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cleaning_services_rounded),
                      label: Text(isClearing ? 'Clearing' : 'Clear cache data'),
                    ),
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

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat, required this.onTap});

  final MeStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapSurface(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _MeColors.textFor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _MeColors.secondaryTextFor(context),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.section, required this.onItemTap});

  final MeSection section;
  final ValueChanged<MeActionItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 7),
          child: Text(
            section.title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _MeColors.secondaryTextFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ),
        _InsetGroup(
          child: Column(
            children: [
              for (var index = 0; index < section.items.length; index++) ...[
                _SettingsCell(
                  item: section.items[index],
                  onTap: () => onItemTap(section.items[index]),
                ),
                if (index != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 58),
                    child: _HorizontalSeparator(),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCell extends StatelessWidget {
  const _SettingsCell({required this.item, required this.onTap});

  final MeActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countLabel = _countLabelForAction(item.title);

    return _TapSurface(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            _Glyph(icon: item.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _MeColors.textFor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _MeColors.secondaryTextFor(context),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (countLabel != null) ...[
              _MiniPill(label: countLabel),
              const SizedBox(width: 8),
            ],
            Icon(
              CupertinoIcons.chevron_forward,
              color: _MeColors.chevronFor(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignOutCell extends StatelessWidget {
  const _SignOutCell({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _InsetGroup(
      child: _TapSurface(
        onTap: onSignOut,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              'Sign Out',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _MeColors.destructiveFor(context),
                fontWeight: FontWeight.w400,
              ),
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
          color: _MeColors.secondaryTextFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _MeColors.textFor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _MeColors.secondaryTextFor(context),
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

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _MeColors.greenSoftFor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _MeColors.green,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _MeColors.green,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

class _TapSurface extends StatelessWidget {
  const _TapSurface({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap ?? () {}, child: child),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _MeColors.surfaceFor(context),
          borderRadius: BorderRadius.circular(12),
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
    return Divider(
      height: 1,
      thickness: 0.7,
      color: _MeColors.separatorFor(context),
    );
  }
}

class _VerticalSeparator extends StatelessWidget {
  const _VerticalSeparator();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: VerticalDivider(
        width: 1,
        thickness: 0.7,
        color: _MeColors.separatorFor(context),
      ),
    );
  }
}

abstract final class _MeColors {
  static const Color background = Color(0xFFF2F2F7);
  static const Color green = Color(0xFF34A853);
  static const Color greenSoft = Color(0xFFEAF7EE);
  static const Color separator = Color(0xFFD9E1DC);
  static const Color text = Color(0xFF111111);
  static const Color secondaryText = Color(0xFF6E6E73);
  static const Color chevron = Color(0xFFC7C7CC);
  static const Color destructive = Color(0xFFFF3B30);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF0C120F) : background;

  static Color surfaceFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF141C17) : Colors.white;

  static Color greenSoftFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF183625) : greenSoft;

  static Color separatorFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF2B3A31) : separator;

  static Color textFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFEAF4EE) : text;

  static Color secondaryTextFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFA8B8AE) : secondaryText;

  static Color chevronFor(BuildContext context) =>
      isDark(context) ? const Color(0xFF6F8175) : chevron;

  static Color destructiveFor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B61) : destructive;
}
