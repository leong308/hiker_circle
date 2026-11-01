// GroupChatDetailPage combines durable messages, read receipts, attachments and team hike actions.
import '../core/services/phone_privacy.dart';
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
import '../core/widgets/loading_toast.dart';
import '../home/Model/hike_session_models.dart';
import 'Data/chat_preference_cache_observer.dart';
import 'View/circle_page.dart';
import 'View/widgets/shared_community_post_card.dart';
part 'View/group_chat_detail_page_screen.dart';
part 'ModelView/group_chat_detail_page_view_model.dart';

part 'Model/group_chat_detail_page_presentation_models.dart';

part 'View/widgets/group_chat_detail_page_widgets.dart';

part 'ModelView/group_chat_detail_page_actions.dart';
