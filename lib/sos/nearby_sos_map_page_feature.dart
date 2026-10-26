// NearbySosMapPage explains nearby alerts and shows walking routes to the selected event.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:url_launcher/url_launcher.dart';

import '../core/services/hiking_route_service.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/map_utils.dart';
import '../core/widgets/map_view_controller.dart';
import '../core/widgets/route_preview_map.dart';
import '../home/View/first_aid_guide_page.dart';
import '../trail/Model/trail_models.dart';
import 'Data/location_snapshot_service.dart';
import 'Model/nearby_sos_event.dart';
import 'Model/sos_models.dart';
part 'View/nearby_sos_map_page_screen.dart';
part 'ModelView/nearby_sos_map_page_view_model.dart';

part 'View/widgets/nearby_sos_map_page_widgets.dart';
