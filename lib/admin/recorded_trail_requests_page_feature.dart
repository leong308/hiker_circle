// RecordedTrailRequestsPage reviews proposed trails derived from recorded hikes.
import 'package:flutter/material.dart';
import '../app/Model/app_session.dart';
import '../app/Data/hiker_circle_firebase_repository.dart';
import '../core/widgets/route_preview_map.dart';
import '../home/Model/hike_session_models.dart';
import '../trail/Model/trail_models.dart';
import '../trail/Model/recorded_trail_request.dart';
import '../trail/Data/trail_duplicate_checker.dart';
import '../trail/View/trail_duplicate_dialog.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'View/admin_ui.dart';
part 'View/recorded_trail_requests_page_screen.dart';
part 'ModelView/recorded_trail_requests_page_view_model.dart';

part 'ModelView/recorded_trail_requests_page_actions.dart';
