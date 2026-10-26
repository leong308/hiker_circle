// QrScannerPage parses HikerCircle profile QR data and confirms the add-buddy action.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/Data/hiker_circle_firebase_repository.dart';
import '../app/Model/app_session.dart';
part 'View/qr_scanner_page_screen.dart';
part 'ModelView/qr_scanner_page_view_model.dart';

part 'ModelView/qr_scanner_page_actions.dart';
