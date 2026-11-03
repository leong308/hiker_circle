// HazardReportPage collects a trail caution, location and supporting evidence for submission.
import 'package:flutter/material.dart';
import 'dart:async';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/caution_icon.dart';
import '../home/View/hike_start_navigation.dart';
import '../sos/Data/location_snapshot_service.dart';
import 'Model/trail_hazard_categories.dart';
import 'Model/trail_models.dart';
import 'View/caution_media.dart';
import '../sos/Model/sos_models.dart';
import 'Data/trail_caution_service.dart';
import 'Model/local_caution_report.dart';

part 'View/hazard_report_page_screen.dart';
part 'ModelView/hazard_report_page_actions.dart';
part 'View/caution_report_history_page.dart';
