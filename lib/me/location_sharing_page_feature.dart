// LocationSharingPage manages the share link and presents the latest device position.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../core/config/google_api_config.dart';
import '../core/widgets/map_controls.dart';
import '../core/widgets/map_view_controller.dart';
import '../core/widgets/map_utils.dart';
import '../core/widgets/route_endpoint_marker.dart';

import '../app/Data/firebase_bootstrap.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/gps_starting_progress.dart';
import 'Data/live_location_sharing_service.dart';
import '../sos/Data/location_snapshot_service.dart';
import '../sos/Model/sos_models.dart';
import '../home/Model/location_update_interval.dart';
part 'View/location_sharing_page_screen.dart';
part 'ModelView/location_sharing_page_view_model.dart';

part 'Model/location_sharing_page_presentation_models.dart';

part 'View/widgets/location_sharing_page_widgets.dart';
