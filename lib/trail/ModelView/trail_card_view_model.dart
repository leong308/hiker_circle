import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Data/trail_card_view_preferences.dart';
import '../Model/trail_card_view.dart';

/// Shares the trail layout across screens and restores it after app restarts.
class TrailCardViewModel extends ChangeNotifier {
  /// Creates layout state with injectable preference access.
  TrailCardViewModel({
    required Future<String?> Function() load,
    required Future<void> Function(String) save,
  }) : _load = load,
       _save = save {
    _ready = _restore();
  }

  static const _preferences = TrailCardViewPreferences();
  static final instance = TrailCardViewModel(
    load: _preferences.load,
    save: _preferences.save,
  );

  final Future<String?> Function() _load;
  final Future<void> Function(String) _save;
  TrailCardView _view = TrailCardView.grid;
  int _selectionRevision = 0;
  bool _disposed = false;
  late final Future<void> _ready;
  Future<void> _writeChain = Future<void>.value();

  /// Returns the current layout immediately, before disk access completes.
  TrailCardView get view => _view;

  /// Completes after the saved preference has been read.
  Future<void> get ready => _ready;

  /// Completes after queued layout writes have finished.
  Future<void> get saved => _writeChain;

  /// Restores the saved value without overwriting a newer user selection.
  Future<void> _restore() async {
    final revision = _selectionRevision;
    try {
      final stored = await _load();
      if (_disposed || revision != _selectionRevision) return;
      final restored = TrailCardView.fromPreference(stored);
      if (_view == restored) return;
      _view = restored;
      notifyListeners();
    } catch (error) {
      debugPrint('Unable to restore the trail layout: $error');
    }
  }

  /// Switches layouts immediately and queues the preference update.
  void toggle() => unawaited(
    select(
      _view == TrailCardView.grid ? TrailCardView.list : TrailCardView.grid,
    ),
  );

  /// Applies a selection locally and serializes writes so the last choice wins.
  Future<void> select(TrailCardView value) {
    if (_disposed) return Future<void>.value();
    _selectionRevision++;
    if (_view != value) {
      _view = value;
      notifyListeners();
    }
    final write = _writeChain.then((_) => _save(value.name));
    _writeChain = write.catchError((Object error) {
      debugPrint('Unable to save the trail layout: $error');
    });
    return _writeChain;
  }

  /// Stops publishing state while allowing pending preference writes to finish.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
