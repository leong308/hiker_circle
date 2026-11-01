// AdminPage routes administrator management, analytics and device debugging sections.
import '../core/widgets/section_label.dart';
import 'Data/admin_safety_repository.dart';
import 'ModelView/admin_safety_view_model.dart';
import 'View/admin_safety_section.dart';
import '../achievements/View/achievement_editor_sheet.dart';
import '../achievements/Model/achievement_catalog.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../app/Data/app_settings_controller.dart';
import '../app/Data/firebase_bootstrap.dart';
import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/page_header_style.dart';
import '../feedback/feedback_page.dart';
import '../me/Data/live_location_sharing_service.dart';
import '../sos/Data/location_snapshot_service.dart';
import 'View/button_debugging_page.dart';
import 'View/admin_ui.dart';
import 'View/admin_analytics_dashboard.dart';
import 'View/recorded_trail_requests_page.dart';
import '../app/Data/local_session_database.dart';

part 'View/admin_page_screen.dart';
part 'ModelView/admin_page_view_model.dart';

part 'Model/admin_page_presentation_models.dart';

part 'View/widgets/admin_page_widgets.dart';

part 'ModelView/admin_page_actions.dart';
