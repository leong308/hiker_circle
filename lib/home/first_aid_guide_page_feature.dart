// FirstAidGuidePage organizes offline first-aid topics, scenarios and step-by-step instructions.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/emergency_number_service.dart';
import '../sos/Data/location_snapshot_service.dart';
part 'View/first_aid_guide_page_screen.dart';
part 'ModelView/first_aid_guide_page_view_model.dart';

part 'Model/first_aid_guide_page_presentation_models.dart';

part 'View/widgets/first_aid_guide_page_widgets.dart';
