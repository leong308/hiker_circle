part of '../qr_scanner_page_feature.dart';

/// Provides typed data actions for this screen without changing repository defaults.
abstract final class _QrScannerPageDataActions {
  /// Binds send buddy request to the selected data source.
  static Future<void> Function({
    required String buddyPhoneNumber,
    required AppSession session,
  })
  sendBuddyRequest(HikerCircleFirebaseRepository receiver) =>
      receiver.sendBuddyRequest;
}
