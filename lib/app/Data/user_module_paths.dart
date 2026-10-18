// UserModule and userModuleDocument keep profile, device, preference and safety Firestore document
// paths consistent.
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore modules are independent cloud records. Local SQLite models and
/// queues keep their existing contracts and do not mirror this hierarchy.
enum UserModule {
  profile,
  devices,
  preferences,
  safety,
  sos,
  location,
  social,
  achievements,
}

DocumentReference<Map<String, dynamic>> userModuleDocument(
  DocumentReference<Map<String, dynamic>> account,
  UserModule module,
) => account.collection('modules').doc(module.name);
