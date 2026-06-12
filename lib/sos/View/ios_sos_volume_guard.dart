import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../Data/sos_device_alert_service.dart';
import '../Model/sos_models.dart';

Future<bool> ensureIosSosOutputVolumeReady({
  required BuildContext context,
  required SosDeviceAlertService deviceAlertService,
  String title = 'Turn Up iPhone Volume',
  String message =
      'HikerCircle uses iPhone media volume for the SOS alarm. Turn up the volume before continuing.',
  String proceedLabel = 'Continue SOS',
}) async {
  final status = await deviceAlertService.getOutputVolumeStatus();
  if (!status.shouldGateForIos || status.isAudible) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }

  final result = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return _IosSosVolumeGuardDialog(
        deviceAlertService: deviceAlertService,
        initialStatus: status,
        title: title,
        message: message,
        proceedLabel: proceedLabel,
      );
    },
  );
  return result == true;
}

class _IosSosVolumeGuardDialog extends StatefulWidget {
  const _IosSosVolumeGuardDialog({
    required this.deviceAlertService,
    required this.initialStatus,
    required this.title,
    required this.message,
    required this.proceedLabel,
  });

  final SosDeviceAlertService deviceAlertService;
  final SosOutputVolumeStatus initialStatus;
  final String title;
  final String message;
  final String proceedLabel;

  @override
  State<_IosSosVolumeGuardDialog> createState() =>
      _IosSosVolumeGuardDialogState();
}

class _IosSosVolumeGuardDialogState extends State<_IosSosVolumeGuardDialog> {
  Timer? _pollTimer;
  late SosOutputVolumeStatus _status;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 650),
      (_) => unawaited(_refreshStatus()),
    );
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    try {
      final nextStatus = await widget.deviceAlertService.getOutputVolumeStatus(
        minimumRequiredVolume: _status.minimumRequiredVolume,
      );
      if (mounted) {
        setState(() {
          _status = nextStatus;
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPercent = _status.outputVolumePercent;
    final requiredPercent = _status.minimumRequiredPercent;
    final canProceed = _status.isAudible;

    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            Text(widget.message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              canProceed
                  ? 'Volume detected: $currentPercent%'
                  : 'Volume must be at least $requiredPercent%',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: canProceed
                    ? const Color(0xFF34A853)
                    : const Color(0xFFE11D48),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _status.outputVolume ?? 0,
              minHeight: 4,
              color: canProceed
                  ? const Color(0xFF34A853)
                  : const Color(0xFFE11D48),
              backgroundColor: const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 10),
            Text(
              canProceed
                  ? 'You can continue.'
                  : 'Use the iPhone volume buttons or Control Center, then wait for this check to update.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: canProceed ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.proceedLabel),
        ),
      ],
    );
  }
}
