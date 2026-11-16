import 'package:flutter/material.dart';

import '../../authentication/View/auth_trail_signal_shell.dart';
import '../../core/widgets/loading_toast.dart';
import '../Data/account_deletion_service.dart';

class AccountDeletionOverlay extends StatelessWidget {
  const AccountDeletionOverlay({super.key, required this.child, this.service});
  final Widget child;
  final AccountDeletionService? service;

  @override
  Widget build(BuildContext context) {
    final controller = service ?? AccountDeletionService.instance;
    return ListenableBuilder(
      listenable: controller,
      child: child,
      builder: (context, child) {
        final phase = controller.phase;
        final thanking =
            phase == AccountDeletionPhase.thanking ||
            phase == AccountDeletionPhase.fading;
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (phase != AccountDeletionPhase.idle)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: phase == AccountDeletionPhase.fading,
                  child: AnimatedOpacity(
                    key: const Key('account-deletion-farewell'),
                    opacity: phase == AccountDeletionPhase.fading ? 0 : 1,
                    duration: controller.fadeDuration,
                    curve: Curves.easeInOut,
                    child: Scaffold(
                      body: AuthTrailSignalShell(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 36,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: .5),
                            ),
                          ),
                          child: thanking
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.favorite_outline_rounded,
                                        size: 48,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'Thank you for hiking with us',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Your account record and Firebase Authentication login have been deleted. You have been signed out.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'Wishing you safe trails ahead.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              : const HikerCircleLoadingView(
                                  message: 'Closing your account…',
                                  detail:
                                      'Please wait while we confirm the request and secure your sign-out.',
                                  compact: true,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
