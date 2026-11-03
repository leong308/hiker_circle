import 'View/hike_safety_settings_form.dart';
import '../trail/View/trail_hazard_alert_dialog.dart';
import '../app/Data/app_settings_controller.dart';
import '../sos/View/fall_detection_test_dialog.dart';
// StartHikeWizardPage chooses a trail before hike mode, timing and safety settings.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'View/solo_hike_distance_dialog.dart';
import 'View/hike_start_navigation.dart';
import 'View/trailhead_proximity_dialog.dart';
import 'ModelView/trailhead_proximity_view_model.dart';
import 'Model/trailhead_proximity.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../core/services/hiking_route_service.dart';
import '../core/services/hiker_ble_service.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/gps_starting_progress.dart';
import '../core/widgets/route_preview_map.dart';
import '../trail/Model/trail_models.dart';
import 'Model/hike_session_models.dart';
import 'Model/hike_arrival_timing.dart';
import 'View/widgets/hike_arrival_time_fields.dart';
import 'Data/location_update_interval_controller.dart';
import 'Data/hike_reminder_permissions.dart';
import 'View/hike_reminder_preferences_sheet.dart';
part 'View/start_hike_wizard_page_screen.dart';
part 'ModelView/start_hike_wizard_page_view_model.dart';

part 'View/widgets/start_hike_wizard_page_widgets.dart';

part 'ModelView/start_hike_wizard_page_actions.dart';
