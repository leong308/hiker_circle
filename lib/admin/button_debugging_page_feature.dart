// ButtonDebuggingPage controls live BLE capture and reviews locally saved debug logs.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/Data/local_session_database.dart';
import '../app/Model/app_session.dart';
import '../core/services/hiker_ble_service.dart';
import 'Data/button_debug_controller.dart';
import 'Model/button_debug_entry.dart';
import 'View/button_debug_entry_card.dart';
import 'View/admin_ui.dart';
part 'View/button_debugging_page_screen.dart';
part 'ModelView/button_debugging_page_view_model.dart';
