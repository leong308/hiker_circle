import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../Model/feedback_report.dart';
import '../feedback_repository.dart';

/// Owns the existing role-scoped feedback subscription and retry behaviour.
class FeedbackInboxViewModel extends ChangeNotifier {
  /// Starts the same latest-100 query used by the existing inbox.
  FeedbackInboxViewModel({
    required FeedbackRepository repository,
    required bool admin,
  }) : _repository = repository,
       _admin = admin {
    _reports = _repository.reports(admin: _admin);
  }

  FeedbackRepository _repository;
  bool _admin;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _reports;
  int _revision = 0;

  /// Supplies the same repository to a selected report's detail page.
  FeedbackRepository get repository => _repository;

  /// Keeps administrator and personal inboxes scoped to their original query.
  Stream<QuerySnapshot<Map<String, dynamic>>> get reports => _reports;

  /// Resets stale stream snapshots when the inbox is refreshed or rebound.
  int get revision => _revision;

  /// Rebinds parent inputs without notifying during a widget rebuild.
  void updateInputs({
    required FeedbackRepository repository,
    required bool admin,
  }) {
    if (identical(repository, _repository) && admin == _admin) return;
    _repository = repository;
    _admin = admin;
    _replaceStream();
  }

  /// Retries a failed subscription without changing its scope or ordering.
  void refresh() {
    _replaceStream();
    notifyListeners();
  }

  /// Replaces the stream and invalidates its previous presentation snapshot.
  void _replaceStream() {
    _reports = _repository.reports(admin: _admin);
    _revision++;
  }

  /// Parses records while retaining the repository's descending date order.
  List<FeedbackReport> parse(QuerySnapshot<Map<String, dynamic>> snapshot) => [
    for (final doc in snapshot.docs)
      FeedbackReport(id: doc.id, data: doc.data()),
  ];
}
