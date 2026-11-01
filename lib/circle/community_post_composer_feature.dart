// CommunityPostEditor shares caption, photo and hike composition across community and end-hike posting.
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/word_limit_formatter.dart';
import 'Model/community_post_limits.dart';
export 'Model/community_post_limits.dart';
part 'View/community_post_composer_screen.dart';
part 'ModelView/community_post_composer_view_model.dart';

part 'Model/community_post_composer_presentation_models.dart';

part 'View/widgets/community_post_composer_widgets.dart';
