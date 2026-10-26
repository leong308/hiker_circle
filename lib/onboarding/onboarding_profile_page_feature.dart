// OnboardingProfilePage collects profile identity, hiking preferences and residential city.
import '../authentication/Data/multi_factor_auth_service.dart';
import '../authentication/View/recent_security_verification_page.dart';
import '../core/widgets/password_capture_protection.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../authentication/Model/password_validator.dart';
import '../core/widgets/loading_toast.dart';
import 'Data/google_city_geocoding_service.dart';
import 'Model/onboarding_profile.dart';
import 'View/residential_city_picker_page.dart';
part 'View/onboarding_profile_page_screen.dart';
part 'ModelView/onboarding_profile_page_view_model.dart';

part 'ModelView/onboarding_profile_page_actions.dart';
