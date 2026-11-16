// PhoneSignInPage switches login/register forms and presents WhatsApp OTP verification.
import 'View/session_security_dialogs.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/services/mobile_security_service.dart';

import 'Data/sign_in_completion_errors.dart';
import 'Data/phone_number_formatter.dart';
import 'Data/privacy_consent_repository.dart';
import '../app/Model/app_session.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/verification_code_input.dart';
import 'Model/auth_status.dart';
import 'Data/auth_flow_diagnostics.dart';
import 'ModelView/auth_view_model.dart';
import 'View/auth_trail_signal_shell.dart';
import 'View/forgot_password_page.dart';
import 'View/inline_notice.dart';
import 'View/security_verification_page.dart';
import 'View/signup_privacy_consent_dialog.dart';
import 'Model/mfa_models.dart';

part 'View/phone_sign_in_page_screen.dart';
part 'ModelView/phone_sign_in_page_view_model.dart';

part 'View/widgets/phone_sign_in_page_widgets.dart';
