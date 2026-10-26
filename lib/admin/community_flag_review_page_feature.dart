// A focused review page keeps detection evidence beside the original content.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../app/Data/local_session_database.dart';
import '../core/widgets/app_toast.dart';
import '../core/widgets/page_header_style.dart';
import 'Model/community_flag.dart';
import 'View/admin_ui.dart';
part 'View/community_flag_review_page_screen.dart';
part 'ModelView/community_flag_review_page_view_model.dart';

part 'Model/community_flag_review_page_presentation_models.dart';

part 'View/widgets/community_flag_review_page_widgets.dart';
