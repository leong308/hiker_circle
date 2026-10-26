// HomeDashboardPage switches between scheduled hike preparation and trail discovery.
import '../core/widgets/page_header_style.dart';
import '../core/widgets/section_label.dart';
import 'dart:async';
import '../core/services/mapbox_travel_distance_service.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../admin/View/admin_ui.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/cached_trail_image.dart';
import '../core/widgets/worldwide_region_picker.dart';
import '../trail/Model/trail_models.dart';
import '../trail/View/trail_card_layout.dart';
import '../trail/View/widgets/trail_card_metrics.dart';
import '../sos/Data/location_snapshot_service.dart';
import '../sos/Model/sos_models.dart';
import 'Model/hike_session_models.dart';
import 'ModelView/fall_stillness_monitor.dart';
import 'View/active_tracking_map_view.dart';
import 'View/next_hike_briefing.dart';
part 'View/home_dashboard_page_screen.dart';
part 'ModelView/home_dashboard_page_view_model.dart';

part 'View/widgets/home_dashboard_page_widgets.dart';
