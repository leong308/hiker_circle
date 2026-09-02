import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/authentication/Data/multi_factor_auth_service.dart';
import 'package:hiker_circle/authentication/Model/mfa_models.dart';
import 'package:hiker_circle/authentication/View/security_verification_page.dart';
import 'package:hiker_circle/core/widgets/loading_toast.dart';

class _UnusedMfaService extends MultiFactorAuthService {}

class _DelayedMfaService extends MultiFactorAuthService {
  final beginTotp = Completer<TotpEnrollment>();
  final verifyTotp = Completer<AppSession>();

  @override
  Future<TotpEnrollment> beginTotpEnrollment({String? mfaToken}) =>
      beginTotp.future;

  @override
  Future<AppSession> verifyTotpLogin({
    required String mfaToken,
    required String code,
  }) => verifyTotp.future;
}

void main() {
  testWidgets('new registration cannot continue without binding a method', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'a' * 43,
            phoneNumber: '+60123456789',
            methods: const [],
            enrollmentRequired: true,
            isNewAccount: true,
            expiresAt: DateTime(2030),
          ),
          service: _UnusedMfaService(),
        ),
      ),
    );

    expect(find.text('One security method is required'), findsOneWidget);
    expect(find.text('Set up Authenticator'), findsOneWidget);
    expect(find.text('Create passkey'), findsOneWidget);
    expect(find.textContaining('skip'), findsNothing);
  });

  testWidgets('login only offers methods already bound to the account', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'b' * 43,
            phoneNumber: '+60123456789',
            methods: const ['totp'],
            enrollmentRequired: false,
            isNewAccount: false,
            expiresAt: DateTime(2030),
          ),
          service: _UnusedMfaService(),
        ),
      ),
    );

    expect(find.text('Use Authenticator'), findsOneWidget);
    expect(find.text('Use passkey'), findsNothing);
  });

  testWidgets('shows the primary loading animation while selecting a method', (
    tester,
  ) async {
    final service = _DelayedMfaService();
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'd' * 43,
            phoneNumber: '+60123456789',
            methods: const [],
            enrollmentRequired: true,
            isNewAccount: true,
            expiresAt: DateTime(2030),
          ),
          service: service,
        ),
      ),
    );

    await tester.tap(find.text('Set up Authenticator'));
    await tester.pump();

    expect(find.byType(HikerCircleLoadingToast), findsOneWidget);
    expect(find.text('Setting up Authenticator…'), findsOneWidget);

    service.beginTotp.complete(
      TotpEnrollment(
        challengeId: 'challenge',
        secret: 'ABC123',
        otpauthUri: 'otpauth://totp/HikerCircle:test?secret=ABC123',
        expiresAt: DateTime(2030),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('6-digit code'), findsOneWidget);
  });

  testWidgets('shows the primary loading animation while verifying a code', (
    tester,
  ) async {
    final service = _DelayedMfaService();
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'e' * 43,
            phoneNumber: '+60123456789',
            methods: const ['totp'],
            enrollmentRequired: false,
            isNewAccount: false,
            expiresAt: DateTime(2030),
          ),
          service: service,
        ),
      ),
    );

    await tester.tap(find.text('Use Authenticator'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify and sign in'));
    await tester.pump();

    expect(find.byType(HikerCircleLoadingToast), findsOneWidget);
    expect(find.text('Verifying security code…'), findsOneWidget);

    service.verifyTotp.complete(
      AppSession(phoneNumber: '+60123456789', signedInAt: DateTime(2030)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SecurityVerificationPage), findsNothing);
  });

  testWidgets(
    'personal-signed iOS enrollment uses Authenticator without launching passkeys',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SecurityVerificationPage(
              continuation: MfaContinuation(
                token: 'c' * 43,
                phoneNumber: '+60123456789',
                methods: const [],
                enrollmentRequired: true,
                isNewAccount: true,
                expiresAt: DateTime(2030),
              ),
              service: _UnusedMfaService(),
            ),
          ),
        );

        expect(find.text('Set up Authenticator'), findsOneWidget);
        expect(find.text('Create passkey'), findsNothing);
        expect(
          find.textContaining('personal-signed iOS build'),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
