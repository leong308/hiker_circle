part of '../qr_scanner_page_feature.dart';

/// Owns the state and non-visual actions of QrScannerPage.
class _QrScannerPageStateViewModel extends ChangeNotifier {
  /// Creates qr scanner page state view model.
  _QrScannerPageStateViewModel({
    required this.readOwnHandle,
    required this.readOwnPhoneNumber,
    required this.effectShowAddBuddyPrompt,
    required this.effectShowOwnQrMessage,
  });
  final String Function() readOwnHandle;
  final String Function() readOwnPhoneNumber;
  final Future<void> Function({
    required String name,
    required String handle,
    required String phoneNumber,
  })
  effectShowAddBuddyPrompt;
  final void Function() effectShowOwnQrMessage;
  bool _disposed = false;

  /// Whether this instance is still active.
  bool get mounted => !_disposed;

  bool stateIsProcessing = false;

  /// Computes on qr detected.
  void commandOnQrDetected(dynamic rawValue) {
    if (!mounted ||
        stateIsProcessing ||
        rawValue is! String ||
        rawValue.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(rawValue);
    if (uri == null || uri.scheme != 'hikercircle') return;

    final isProfileQr =
        uri.host == 'buddy' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'add';
    final handle = isProfileQr
        ? uri.queryParameters['h']?.trim() ?? ''
        : uri.host;
    final name = isProfileQr
        ? uri.queryParameters['n']?.trim() ?? handle
        : uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : handle;
    final phone = isProfileQr
        ? uri.queryParameters['p']?.trim() ??
              uri.queryParameters['phone']?.trim() ??
              ''
        : '';

    if (handle.isEmpty && name.isEmpty) return;

    if (handle.toLowerCase() == readOwnHandle().toLowerCase() ||
        commandSamePhone(phone, readOwnPhoneNumber())) {
      effectShowOwnQrMessage();
      return;
    }

    unawaited(
      effectShowAddBuddyPrompt(name: name, handle: handle, phoneNumber: phone),
    );
  }

  /// Computes same phone.
  bool commandSamePhone(String first, String second) {
    final firstKey = first.replaceAll(RegExp(r'[^0-9]'), '');
    final secondKey = second.replaceAll(RegExp(r'[^0-9]'), '');
    return firstKey.isNotEmpty && firstKey == secondKey;
  }

  /// Releases resources owned by this instance.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
