// SecurityMethodsPage manages authenticator and passkey enrollment for the signed-in account.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/widgets/loading_toast.dart';
import '../core/widgets/verification_code_input.dart';

import 'Data/multi_factor_auth_service.dart';
import 'Data/passkey_build_support.dart';
import 'Model/mfa_models.dart';
import 'View/recent_security_verification_page.dart';
import '../app/Model/app_session.dart';

part 'View/security_methods_page_screen.dart';
part 'ModelView/security_methods_page_view_model.dart';

part 'ModelView/security_methods_page_actions.dart';
