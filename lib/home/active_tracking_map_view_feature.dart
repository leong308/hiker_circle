// ActiveTrackingMapView draws recorded movement, team positions and checkpoints.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/widgets/community_hazard_marker.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../app/Data/local_session_database.dart';
import '../core/services/static_hazard_dataset_service.dart';
import '../core/widgets/map_controls.dart';
import '../core/widgets/map_utils.dart';
import '../core/widgets/route_endpoint_marker.dart';
import '../core/widgets/route_preview_camera.dart';
import '../core/widgets/static_hazard_marker.dart';
import '../trail/Model/trail_models.dart';
import 'Data/active_hike_weather_service.dart';
import 'Model/hike_session_models.dart';
import 'Model/active_hike_map_mode.dart';
part 'View/active_tracking_map_view_screen.dart';
part 'ModelView/active_tracking_map_view_view_model.dart';

part 'View/widgets/active_tracking_map_view_widgets.dart';
