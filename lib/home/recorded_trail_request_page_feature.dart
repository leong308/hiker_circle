// RecordedTrailRequestPage names recorded checkpoints and submits a proposed trail for review.
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../app/Model/app_session.dart';
import '../app/Data/hiker_circle_firebase_repository.dart';
import '../core/widgets/route_preview_map.dart';
import '../core/widgets/page_header_style.dart';
import 'Model/hike_session_models.dart';
import 'Model/recorded_hike_map_points.dart';
part 'View/recorded_trail_request_page_screen.dart';
part 'ModelView/recorded_trail_request_page_actions.dart';
