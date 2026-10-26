// TrailCautionDetailsSheet displays caution evidence and exposes the allowed resolution actions.
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/widgets/caution_icon.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/community_hazard_marker.dart';
import '../home/View/hike_start_navigation.dart';
import 'Data/trail_caution_service.dart';
import 'Data/trail_caution_details_repository.dart';
import 'Model/caution_update.dart';
import 'ModelView/trail_caution_details_view_model.dart';
import 'Model/trail_hazard_categories.dart';
import 'View/caution_media.dart';
part 'View/trail_caution_details_screen.dart';

part 'View/widgets/trail_caution_details_widgets.dart';
part 'View/widgets/caution_report_card.dart';
