import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../Model/sos_delivery_policy.dart';
import '../Model/sos_models.dart';

/// Reads server-owned SOS receipts; provider requests and retries remain on Firebase.
class SosConfirmationStore {
  /// Uses the authenticated app's Firestore instance.
  SosConfirmationStore(this.firestore, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final FirebaseFirestore firestore;
  final DateTime Function() _now;
  static final _alerts = <String, Map<String, SosAlert>>{};
  static final _receipts = <String, List<Map<String, dynamic>>>{};

  /// Returns only this account's contact outcomes.
  CollectionReference<Map<String, dynamic>> collection(String owner) =>
      firestore
          .collection('sosDeliveryReceipts')
          .doc(owner)
          .collection('dispatches');

  /// Keeps local submission metadata while applying newer, authoritative contact results.
  SosAlert remember(String owner, SosAlert alert) {
    final merged = SosDeliveryPolicy.merge(
      alert,
      (_receipts[owner] ?? const []).where((r) => r['alertId'] == alert.id),
      now: _now(),
    );
    (_alerts[owner] ??= {})[alert.id] = merged;
    return merged;
  }

  /// Refreshes receipts before history loads or a durable client retry.
  Future<void> refresh(String owner) async {
    // Query recent SOS delivery receipts
    final snapshot = await collection(
      owner,
    ).orderBy('triggeredAtMillis', descending: true).limit(300).get();
    _receipts[owner] = snapshot.docs.map((d) => d.data()).toList();
  }

  /// Reconciles cached retry rows by phone identity, including late confirmations after relaunch.
  List<SosContactDispatch> contacts(
    String owner,
    String alertId,
    List<SosContactDispatch> previous,
  ) {
    final byPhone = {
      for (final p in previous) SosDeliveryPolicy.key(p.phoneNumber): p,
    };
    for (final r in (_receipts[owner] ?? const <Map<String, dynamic>>[]).where(
      (r) => r['alertId'] == alertId,
    )) {
      final p = SosDeliveryPolicy.contact(r, now: _now());
      final old = byPhone[SosDeliveryPolicy.key(p.phoneNumber)];
      if (old == null || p.updatedAtMillis >= old.updatedAtMillis) {
        byPhone[SosDeliveryPolicy.key(p.phoneNumber)] = p;
      }
    }
    return byPhone.values.toList();
  }

  /// Shows Unconfirmed at the deadline locally, then accepts later server revisions.
  Stream<SosAlert> watch(String owner) => Stream.multi((output) {
    Timer? timer;
    var revision = 0;
    var closed = false;

    /// Publishes the current receipt snapshot and schedules its next 15-second deadline.
    Future<void> publish() async {
      final generation = ++revision;
      timer?.cancel();
      final records = _receipts[owner] ?? const <Map<String, dynamic>>[];
      final now = _now().millisecondsSinceEpoch;
      final deadlines =
          records
              .where((r) => r['status'] == 'sending')
              .map(
                (r) => (r['confirmationDeadlineMillis'] as num?)?.toInt() ?? 0,
              )
              .where((d) => d > now)
              .toList()
            ..sort();
      // Arm the deadline before any history reads; a slow network must not delay Unconfirmed.
      if (deadlines.isNotEmpty) {
        timer = Timer(Duration(milliseconds: deadlines.first - now), publish);
      }
      final ids =
          records.map((r) => r['alertId']).whereType<String>().toSet().toList()
            ..sort(
              (a, b) => (_alerts[owner]?.containsKey(b) == true ? 1 : 0)
                  .compareTo(_alerts[owner]?.containsKey(a) == true ? 1 : 0),
            );
      for (final id in ids) {
        var base = _alerts[owner]?[id];
        if (base == null) {
          try {
            // Query alert linked to delivery receipt
            final document = await firestore
                .collection('sosAlerts')
                .doc(id)
                .get()
                .timeout(const Duration(seconds: 2));
            if (document.exists && document.data()?['userId'] == owner) {
              base = SosAlert.fromFirestore(document.data()!);
            }
          } catch (_) {
            // A locally pending alert may not have its cloud log yet.
          }
        }
        if (closed || generation != revision) return;
        if (base != null) output.add(remember(owner, base));
      }
    }

    // Query live SOS delivery receipts
    final subscription = collection(owner)
        .orderBy('triggeredAtMillis', descending: true)
        .limit(300)
        .snapshots()
        .listen((snapshot) {
          _receipts[owner] = snapshot.docs.map((d) => d.data()).toList();
          unawaited(publish());
        }, onError: output.addError);
    output.onCancel = () {
      closed = true;
      revision++;
      timer?.cancel();
      unawaited(subscription.cancel());
    };
  });
}
