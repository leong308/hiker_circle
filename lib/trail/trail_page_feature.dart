// TrailPage browses trails and opens route, forecast, caution, review and trail editing flows.
export 'View/hazard_report_page.dart';
import 'View/trail_caution_details.dart';
import '../core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Data/local_session_database.dart';
import '../app/Model/app_session.dart';
import '../core/services/hiking_route_service.dart';
import '../core/widgets/cached_trail_image.dart';
import '../core/widgets/section_label.dart';
import '../core/widgets/existing_trail_path_overlay.dart';
import '../core/widgets/map_controls.dart';
import '../core/widgets/map_view_controller.dart';
import '../core/widgets/state_boundary_overlay.dart';
import '../core/widgets/map_utils.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/route_preview_map.dart';
import '../core/widgets/route_checkpoint_progress.dart';
import '../core/widgets/worldwide_region_picker.dart';
import 'Model/trail_models.dart';
import 'Data/local_trail_paths.dart';
import 'Data/trail_duplicate_checker.dart';
import 'Data/trail_start_location_resolver.dart';
import 'Model/malaysia_map_region.dart';
import 'View/trail_weather_panel.dart';
import 'View/checkpoint_flow.dart';
import 'View/trail_card_layout.dart';
import 'View/trail_images_card.dart';
import 'View/trail_location_summary.dart';
import 'View/trail_duplicate_dialog.dart';
part 'View/trail_page_screen.dart';
part 'ModelView/trail_page_view_model.dart';

part 'Model/trail_page_presentation_models.dart';

part 'View/widgets/trail_page_widgets.dart';

part 'ModelView/trail_page_actions.dart';
