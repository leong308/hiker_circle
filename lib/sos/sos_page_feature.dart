import 'View/fall_detection_test_dialog.dart';
// SosPage coordinates manual countdowns, queued alert feedback, device alerts and nearby emergencies.
import '../core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/Data/firebase_bootstrap.dart';
import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../home/View/first_aid_guide_page.dart';
import '../home/View/gears_required_page.dart';
import '../home/View/hike_start_navigation.dart';
import '../me/View/location_sharing_page.dart';
import '../core/services/hiker_ble_service.dart';
import '../core/services/network_reachability_service.dart';
import '../core/widgets/loading_toast.dart';
import 'Data/emergency_contacts_repository.dart';
import 'Data/location_snapshot_service.dart';
import 'Data/nearby_sos_event_repository.dart';
import 'Data/sos_alert_repository.dart';
import 'Data/sos_device_alert_service.dart';
import 'Model/sos_models.dart';
import 'Model/sos_presentation_controller.dart';
import 'Model/nearby_sos_event.dart';
import 'ModelView/sos_view_model.dart';
import 'View/emergency_contacts_page.dart';
import 'View/ios_sos_volume_guard.dart';
import 'View/nearby_sos_map_page.dart';
import 'View/paired_sos_button_page.dart';
part 'View/sos_page_screen.dart';
part 'ModelView/sos_page_view_model.dart';

part 'Model/sos_page_presentation_models.dart';

part 'View/widgets/sos_page_widgets.dart';
