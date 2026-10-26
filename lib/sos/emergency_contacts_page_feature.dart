// EmergencyContactsPage edits emergency recipients and imports selected device contacts.
import 'package:hiker_circle/core/widgets/page_header_style.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/Model/app_session.dart';
import '../authentication/Data/phone_number_formatter.dart';
import '../core/widgets/loading_toast.dart';
import 'Data/emergency_contacts_repository.dart';
import 'Data/sos_device_alert_service.dart';
import 'Model/sos_models.dart';
import 'ModelView/emergency_contacts_view_model.dart';
part 'View/emergency_contacts_page_screen.dart';
part 'ModelView/emergency_contacts_page_view_model.dart';

part 'View/widgets/emergency_contacts_page_widgets.dart';
