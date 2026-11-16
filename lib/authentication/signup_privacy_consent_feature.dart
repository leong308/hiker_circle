import 'dart:async';

import 'package:flutter/material.dart';

import '../core/widgets/loading_toast.dart';
import '../core/widgets/privacy_policy_link.dart';
import 'Data/privacy_consent_repository.dart';

part 'View/signup_privacy_consent_dialog_screen.dart';
part 'ModelView/signup_privacy_consent_view_model.dart';

/// Reads only local storage before showing the notice. The phone number is not
/// sent to Firebase or a verification provider by this step.
Future<bool> requestSignupPrivacyConsent(
  BuildContext context, {
  required String phoneNumber,
  required PrivacyConsentRepository repository,
}) async {
  try {
    if (await repository.load(phoneNumber) != null) return true;
  } catch (_) {
    // Show the retryable local-storage error inside the notice.
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => SignupPrivacyConsentDialog(
          ownerPhoneNumber: phoneNumber,
          repository: repository,
        ),
      ) ==
      true;
}
