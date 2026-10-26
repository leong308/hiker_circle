// ResidentialCityPickerPage searches and confirms a geocoded residential city selection.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../core/widgets/map_controls.dart';
import '../core/widgets/map_view_controller.dart';
import '../core/widgets/map_utils.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/state_boundary_overlay.dart';
import '../trail/Model/malaysia_map_region.dart';
import 'Data/google_city_geocoding_service.dart';
part 'View/residential_city_picker_page_screen.dart';
part 'ModelView/residential_city_picker_page_view_model.dart';
