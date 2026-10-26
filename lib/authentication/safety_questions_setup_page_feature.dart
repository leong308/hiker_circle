// SafetyQuestionsSetupPage collects and confirms account recovery questions and answers.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../core/widgets/loading_toast.dart';

import 'Model/safety_questions.dart';
import 'Data/multi_factor_auth_service.dart';
import 'View/recent_security_verification_page.dart';
part 'View/safety_questions_setup_page_screen.dart';
part 'ModelView/safety_questions_setup_page_actions.dart';
