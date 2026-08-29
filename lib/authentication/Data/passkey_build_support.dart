import 'package:flutter/foundation.dart';

/// Native iOS passkeys require a provisioning profile that authorizes the
/// Associated Domains entitlement. Free Apple-account (Personal Team) signing
/// cannot authorize that capability, so personal-signed builds keep this off.
///
/// A paid-team build may opt in only after selecting an entitlements file that
/// contains `webcredentials:<relying-party-domain>`:
///
/// `--dart-define=IOS_NATIVE_PASSKEYS_ENABLED=true`
const bool _iosNativePasskeysEnabled = bool.fromEnvironment(
  'IOS_NATIVE_PASSKEYS_ENABLED',
  defaultValue: false,
);

bool nativePasskeysEnabledForBuild({
  bool? isWeb,
  TargetPlatform? platform,
  bool iosNativePasskeysEnabled = _iosNativePasskeysEnabled,
}) {
  if (isWeb ?? kIsWeb) return true;
  final resolvedPlatform = platform ?? defaultTargetPlatform;
  if (resolvedPlatform == TargetPlatform.iOS) {
    return iosNativePasskeysEnabled;
  }
  return true;
}

class PasskeysUnavailableForBuildException implements Exception {
  const PasskeysUnavailableForBuildException();
}

const String personalSigningPasskeyMessage =
    'Passkeys are unavailable in this personal-signed iOS build. '
    'Use Authenticator instead. Native iOS passkeys require an Apple '
    'Developer Program signing profile with Associated Domains.';
