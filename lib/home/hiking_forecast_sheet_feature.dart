// HikingForecastSheet explores the selected hike's hourly conditions, charts and precaution details.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/widgets/page_header_style.dart';
import '../core/widgets/caution_icon.dart';
import '../trail/Model/trail_models.dart';
import '../trail/View/weather_presentation.dart';
import 'Data/hike_briefing_weather_service.dart';
import 'Data/home_screen_widget_service.dart';
import 'Model/hike_session_models.dart';
import 'Model/hike_weather_briefing.dart';
import 'Model/session_weather_forecast.dart';
part 'View/hiking_forecast_sheet_screen.dart';
part 'ModelView/hiking_forecast_sheet_view_model.dart';
