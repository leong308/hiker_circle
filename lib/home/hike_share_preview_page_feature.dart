// HikeSharePreviewPage previews a completed hike using the shared community composer and durable draft.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../circle/View/community_post_composer.dart';
import '../core/widgets/route_preview_map.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/word_limit_formatter.dart';
import 'Data/hike_share_card_renderer.dart';
import 'Model/hike_session_models.dart';
import 'Model/recorded_hike_map_points.dart';
part 'View/hike_share_preview_page_screen.dart';
part 'ModelView/hike_share_preview_page_view_model.dart';

part 'View/widgets/hike_share_preview_page_widgets.dart';
