// ForgotPasswordPage guides phone OTP, recovery method verification and password replacement.
import '../core/widgets/password_capture_protection.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/widgets/loading_toast.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/verification_code_input.dart';

import 'Data/passkey_build_support.dart';
import 'ModelView/auth_view_model.dart';
import 'View/inline_notice.dart';
part 'View/forgot_password_page_screen.dart';
part 'ModelView/forgot_password_page_view_model.dart';

part 'View/widgets/forgot_password_page_widgets.dart';
