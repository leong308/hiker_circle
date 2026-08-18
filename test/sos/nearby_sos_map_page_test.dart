import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/sos/Model/nearby_sos_event.dart';
import 'package:hiker_circle/sos/Model/sos_models.dart';
import 'package:hiker_circle/sos/View/nearby_sos_map_page.dart';

void main() {
  test('builds the walking route from the phone to the reported SOS', () {
    final receivedAt = DateTime.utc(2026, 8, 18, 12);
    final event = NearbySosEvent(
      ownerPhoneNumber: '+60111111111',
      eventKey: 'button-a:7',
      deviceId: 'button-a',
      receivedAt: receivedAt,
      updatedAt: receivedAt,
      location: const SosTriggerLocation(latitude: 5.4200, longitude: 100.3288),
    );
    const phoneLocation = SosTriggerLocation(
      latitude: 5.4141,
      longitude: 100.3288,
    );

    final trail = buildNearbySosRouteTrail(
      event: event,
      phoneLocation: phoneLocation,
    );

    expect(trail.checkpoints, hasLength(2));
    expect(trail.checkpoints.first.name, 'Your phone');
    expect(trail.checkpoints.first.latitude, phoneLocation.latitude);
    expect(trail.checkpoints.first.longitude, phoneLocation.longitude);
    expect(trail.checkpoints.last.name, 'Reported SOS');
    expect(trail.checkpoints.last.latitude, event.location!.latitude);
    expect(trail.checkpoints.last.longitude, event.location!.longitude);
    expect(trail.distanceKm, greaterThan(0));
    expect(trail.estimatedDurationMinutes, greaterThan(0));
  });

  test('rejects route creation when the SOS has no reported GPS', () {
    final receivedAt = DateTime.utc(2026, 8, 18, 12);
    final event = NearbySosEvent(
      ownerPhoneNumber: '+60111111111',
      eventKey: 'button-a:7',
      deviceId: 'button-a',
      receivedAt: receivedAt,
      updatedAt: receivedAt,
    );

    expect(
      () => buildNearbySosRouteTrail(
        event: event,
        phoneLocation: const SosTriggerLocation(
          latitude: 5.4141,
          longitude: 100.3288,
        ),
      ),
      throwsArgumentError,
    );
  });
}
