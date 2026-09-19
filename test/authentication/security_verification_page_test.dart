import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/app/Model/app_session.dart';
import 'package:hiker_circle/authentication/Data/multi_factor_auth_service.dart';
import 'package:hiker_circle/authentication/Model/mfa_models.dart';
import 'package:hiker_circle/authentication/View/security_verification_page.dart';
import 'package:hiker_circle/core/widgets/loading_toast.dart';
import 'package:hiker_circle/core/widgets/verification_code_input.dart';

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
  testWidgets('unfinished existing registration resumes factor enrollment', (
    tester,
  ) async {
    final service = _DelayedMfaService();
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'r' * 43,
            phoneNumber: '+60123456789',
            methods: const [],
            enrollmentRequired: true,
            isNewAccount: false,
            expiresAt: DateTime(2030),
          ),
          service: service,
        ),
      ),
    );
    expect(find.text('Protect your account'), findsOneWidget);
    await tester.tap(find.text('Set up Authenticator'));
    await tester.pump();
    service.beginTotp.complete(
      TotpEnrollment(
        challengeId: 'resumed',
        secret: 'ABC123',
        otpauthUri: 'otpauth://totp/HikerCircle:test?secret=ABC123',
        expiresAt: DateTime(2030),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VerificationCodeInput), findsOneWidget);
    expect(find.text('Use Authenticator'), findsNothing);
  });

  testWidgets('verification overlay fills the screen as the keyboard closes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    final service = _DelayedMfaService();
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityVerificationPage(
          continuation: MfaContinuation(
            token: 'f' * 43,
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
    tester.view.viewInsets = FakeViewPadding(bottom: 320);
    await tester.pump();
    final input = find
        .descendant(
          of: find.byType(VerificationCodeInput),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(input, '123456');
    await tester.pump();
    await tester.pump();

    final barrier = find.descendant(
      of: find.byType(HikerCircleLoadingToastOverlay),
      matching: find.byType(AbsorbPointer),
    );
    const screen = Rect.fromLTWH(0, 0, 430, 932);
    expect(tester.getRect(barrier), screen);
    expect(tester.testTextInput.isVisible, isFalse);

    tester.view.viewInsets = FakeViewPadding();
    await tester.pump();
    expect(tester.getRect(barrier), screen);
    final card = tester.getRect(
      find.byKey(const Key('hiker-circle-loading-toast')),
    );
    expect(card.center, screen.center);
    expect(tester.takeException(), isNull);
    service.verifyTotp.completeError(StateError('Test verification failed'));
    await tester.pumpAndSettle();
    expect(find.byType(HikerCircleLoadingToastOverlay), findsNothing);
  });

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
    expect(find.byType(VerificationCodeInput), findsOneWidget);
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
    await tester.enterText(
      find
          .descendant(
            of: find.byType(VerificationCodeInput),
            matching: find.byType(TextField),
          )
          .first,
      '123456',
    );
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
