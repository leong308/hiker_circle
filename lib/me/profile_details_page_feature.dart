// ProfileDetailsPage edits public hiker details and crops the selected profile photo.
import '../core/widgets/section_label.dart';
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/Data/firebase_bootstrap.dart';
import '../app/Data/conditional_cloud_cache.dart';
import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Data/local_session_database.dart';
import '../app/Model/app_session.dart';
import '../core/widgets/loading_toast.dart';
import '../onboarding/Data/onboarding_repository.dart';
import '../onboarding/Data/google_city_geocoding_service.dart';
import '../onboarding/Model/onboarding_profile.dart';
import '../onboarding/View/residential_city_picker_page.dart';
part 'View/profile_details_page_screen.dart';
part 'ModelView/profile_details_page_view_model.dart';

part 'View/widgets/profile_details_page_widgets.dart';

part 'ModelView/profile_details_page_actions.dart';

part 'Model/profile_details_page_presentation_models.dart';
