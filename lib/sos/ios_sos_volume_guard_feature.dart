// ensureIosSosOutputVolumeReady checks audible emergency output before continuing on iOS.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'Data/sos_device_alert_service.dart';
import 'Model/sos_models.dart';
part 'View/ios_sos_volume_guard_screen.dart';
part 'ModelView/ios_sos_volume_guard_view_model.dart';
