import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/Data/hiker_circle_firebase_repository.dart';
import '../../app/Model/app_session.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({
    super.key,
    required this.session,
    required this.repository,
    required this.ownPhoneNumber,
    required this.ownHandle,
  });

  final AppSession session;
  final HikerCircleFirebaseRepository repository;
  final String ownPhoneNumber;
  final String ownHandle;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  static const _eventChannel = EventChannel('hiker_circle/qr_scanner_events');
  bool _isProcessing = false;
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_onQrDetected);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onQrDetected(dynamic rawValue) {
    if (_isProcessing || rawValue is! String || rawValue.isEmpty) return;

    final uri = Uri.tryParse(rawValue);
    if (uri == null || uri.scheme != 'hikercircle') return;

    final isProfileQr =
        uri.host == 'buddy' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'add';
    final handle = isProfileQr
        ? uri.queryParameters['h']?.trim() ?? ''
        : uri.host;
    final name = isProfileQr
        ? uri.queryParameters['n']?.trim() ?? handle
        : uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : handle;
    final phone = isProfileQr
        ? uri.queryParameters['p']?.trim() ??
              uri.queryParameters['phone']?.trim() ??
              ''
        : '';

    if (handle.isEmpty && name.isEmpty) return;

    if (handle.toLowerCase() == widget.ownHandle.toLowerCase() ||
        _samePhone(phone, widget.ownPhoneNumber)) {
      _showOwnQrMessage();
      return;
    }

    _showAddBuddyPrompt(name: name, handle: handle, phoneNumber: phone);
  }

  void _showOwnQrMessage() {
    setState(() => _isProcessing = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('That is your own HikerCircle QR. No action taken.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    });
  }

  Future<void> _showAddBuddyPrompt({
    required String name,
    required String handle,
    required String phoneNumber,
  }) async {
    setState(() => _isProcessing = true);

    final shouldAdd = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF7EE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Color(0xFF34A853),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Add $name as a buddy?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  handle.isEmpty
                      ? 'This QR belongs to a HikerCircle profile.'
                      : '$handle can be added to your Trail Buddies for future team hikes and shared trail plans.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6E6E73),
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Not Now'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Add Buddy'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    if (shouldAdd == true) {
      if (phoneNumber.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('This QR is missing a phone number.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        setState(() => _isProcessing = false);
        return;
      }

      try {
        await widget.repository.sendBuddyRequest(
          session: widget.session,
          buddyPhoneNumber: phoneNumber,
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Unable to send buddy request: $error'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        setState(() => _isProcessing = false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Friend request sent to $name.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    } else {
      setState(() => _isProcessing = false);
    }
  }

  bool _samePhone(String first, String second) {
    final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
    final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
    return firstKey.isNotEmpty && firstKey == secondKey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scan QR',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (defaultTargetPlatform == TargetPlatform.iOS)
            UiKitView(
              viewType: 'hiker_circle/qr_scanner',
              creationParams: null,
              creationParamsCodec: const StandardMessageCodec(),
            )
          else if (defaultTargetPlatform == TargetPlatform.android)
            AndroidView(
              viewType: 'hiker_circle/qr_scanner',
              creationParams: null,
              creationParamsCodec: const StandardMessageCodec(),
            )
          else
            const Center(
              child: Text(
                'QR scanning is only available on iOS and Android.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          if (_isProcessing)
            Container(color: Colors.black54),
        ],
      ),
    );
  }
}
