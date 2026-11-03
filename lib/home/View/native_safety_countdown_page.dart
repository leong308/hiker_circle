import 'dart:async';
import 'package:flutter/material.dart';

/// Foreground iOS counterpart of Android's native SafetyAlertActivity.
class NativeSafetyCountdownPage extends StatefulWidget {
  const NativeSafetyCountdownPage({
    super.key,
    required this.deadline,
    required this.isStillness,
    required this.onCancel,
    required this.onExpired,
  });
  final DateTime deadline;
  final bool isStillness;
  final Future<void> Function() onCancel;
  final VoidCallback onExpired;

  @override
  State<NativeSafetyCountdownPage> createState() =>
      _NativeSafetyCountdownPageState();
}

class _NativeSafetyCountdownPageState extends State<NativeSafetyCountdownPage> {
  Timer? _timer;
  bool _cancelling = false, _expired = false;
  String? _error;
  int get _seconds =>
      (widget.deadline
                  .toUtc()
                  .difference(DateTime.now().toUtc())
                  .inMilliseconds /
              1000)
          .ceil()
          .clamp(0, 86400);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  void _tick() {
    if (!mounted || _expired) return;
    setState(() {});
    if (_seconds == 0) {
      _expired = true;
      _timer?.cancel();
      widget.onExpired();
    }
  }

  Future<void> _cancel() async {
    if (_cancelling || _expired || _seconds == 0) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await widget.onCancel();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not confirm. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFE8DC);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF240F1C),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF240F1C), Color(0xFF6D1830), Color(0xFFB73640)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'HIKERCIRCLE SAFETY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Column(
                            children: [
                              Container(
                                width: 126,
                                height: 126,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [cream, Color(0xFFFFC6BF)],
                                  ),
                                ),
                                child: const Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF842039),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                widget.isStillness
                                    ? 'Are you okay?'
                                    : 'Possible fall detected',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.isStillness
                                    ? 'Prolonged-stillness SOS'
                                    : 'Fall SOS',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFDAD7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '$_seconds',
                                key: const Key('native-safety-seconds'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 72,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'seconds until SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Confirm that you are safe before the countdown ends to cancel SOS.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            FilledButton(
                              key: const Key('native-safety-cancel'),
                              onPressed:
                                  _cancelling || _expired || _seconds == 0
                                  ? null
                                  : _cancel,
                              style: FilledButton.styleFrom(
                                backgroundColor: cream,
                                foregroundColor: const Color(0xFF842039),
                                minimumSize: const Size.fromHeight(74),
                                padding: const EdgeInsets.all(20),
                              ),
                              child: Text(
                                _cancelling
                                    ? 'Cancelling SOS…'
                                    : 'I’m safe — cancel SOS',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'No SOS has been sent yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
