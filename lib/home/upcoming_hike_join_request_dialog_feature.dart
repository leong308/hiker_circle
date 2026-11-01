// UpcomingHikeJoinRequestDialog presents requester details and the host's join decision.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../core/widgets/loading_toast.dart';
import '../core/widgets/section_label.dart';
import 'Model/hike_session_models.dart';
import 'Model/hike_join_request_stats.dart';
import 'View/widgets/hike_join_request_stats.dart';
part 'View/upcoming_hike_join_request_dialog_screen.dart';
part 'ModelView/upcoming_hike_join_request_dialog_view_model.dart';
