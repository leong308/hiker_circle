// HikerCircleApp applies settings and selects startup, authentication or the signed-in shell.
import '../authentication/View/session_security_dialogs.dart';
import '../core/widgets/password_capture_protection.dart';
import 'Data/local_session_database.dart';
import 'View/private_screen_unlock_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/widgets/page_header_style.dart';
import 'package:feedback/feedback.dart';

import '../authentication/View/phone_sign_in_page.dart';
import '../core/widgets/loading_toast.dart';
import '../feedback/feedback_capture_form.dart';
import '../home/View/hiker_home_page.dart';
import '../me/Data/account_deletion_service.dart';
import '../me/View/account_deletion_overlay.dart';
import '../onboarding/View/first_time_onboarding_flow.dart';
import 'Data/app_settings_controller.dart';
import 'Data/firebase_bootstrap.dart';
import 'Data/firebase_user_repository.dart';
import 'Data/session_repository.dart';
import 'ModelView/app_view_model.dart';
part 'View/hiker_circle_app_screen.dart';
part 'ModelView/hiker_circle_app_view_model.dart';
