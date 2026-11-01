// RecentSecurityVerificationPage confirms a current security factor before sensitive account changes.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'package:flutter/material.dart';

import '../app/Model/app_session.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/verification_code_input.dart';
import 'Data/phone_number_formatter.dart';
import 'Model/auth_status.dart';
import 'ModelView/auth_view_model.dart';
import 'View/inline_notice.dart';
import 'View/security_verification_page.dart';
import 'Model/mfa_models.dart';

part 'View/recent_security_verification_page_screen.dart';
part 'ModelView/recent_security_verification_page_view_model.dart';
