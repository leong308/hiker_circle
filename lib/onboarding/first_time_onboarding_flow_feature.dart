// FirstTimeOnboardingFlow sequences required profile and safety setup after account creation.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/Data/firebase_bootstrap.dart';
import '../app/Model/app_session.dart';
import '../authentication/View/safety_questions_setup_page.dart';
import '../core/widgets/loading_toast.dart';
import '../sos/Data/emergency_contacts_repository.dart';
import '../sos/Model/sos_models.dart';
import '../sos/View/emergency_contacts_page.dart';
import 'Data/onboarding_repository.dart';
import 'Model/onboarding_profile.dart';
import 'View/onboarding_profile_page.dart';
part 'View/first_time_onboarding_flow_screen.dart';
part 'ModelView/first_time_onboarding_flow_view_model.dart';
