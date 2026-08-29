import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/authentication/Data/multi_factor_auth_service.dart';
import 'package:hiker_circle/authentication/Model/mfa_models.dart';
import 'package:hiker_circle/authentication/View/security_verification_page.dart';

class _UnusedMfaService extends MultiFactorAuthService {}

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
}
