import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hiker_circle/core/services/weather_area_service.dart';
import 'package:hiker_circle/core/services/weather_map_service.dart';

void main() {
  test('fixed 50 km extent and zoom are independent of camera zoom', () {
    for (final location in [(5.4, 100.3), (3.1, 101.7), (6.1, 116.5)]) {
      final grid = WeatherAreaGrid(location.$1, location.$2);
      expect(grid.tileCount, inInclusiveRange(1, 4));
      expect(grid.corners[0][0], lessThan(location.$2 - .44));
      expect(grid.corners[1][0], greaterThan(location.$2 + .44));
      expect(grid.corners[0][1], greaterThan(location.$1 + .44));
      expect(grid.corners[2][1], lessThan(location.$1 - .44));
      expect(WeatherAreaGrid.zoom, 8);
    }
  });

  testWidgets(
    'one area download is reused; faint rain is strengthened and outside 50km stays transparent',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 16, 16),
          ui.Paint()..color = const ui.Color.fromARGB(16, 80, 80, 225),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        final png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        var calls = 0;
        var now = DateTime.utc(2026, 9, 14);
        final service = WeatherAreaService(
          now: () => now,
          client: MockClient((request) async {
            calls++;
            expect(request.url.path, startsWith('/map/precipitation_new/8/'));
            return http.Response.bytes(png, 200);
          }),
        );
        Future<WeatherAreaImage> load({bool refresh = false}) => service.load(
          latitude: 5.4,
          longitude: 100.3,
          layer: WeatherMapLayer.rain,
          apiKey: 'test',
          refresh: refresh,
        );
        final simultaneous = await Future.wait([load(), load()]);
        final area = simultaneous.first;
        final count = area.grid.tileCount;
        expect(calls, count);
        expect(identical(area, simultaneous.last), isTrue);
        expect(identical(await load(), area), isTrue);
        expect(calls, count);
        final codec = await ui.instantiateImageCodec(area.png);
        final result = (await codec.getNextFrame()).image;
        final rgba = (await result.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = ((WeatherAreaGrid.tileX(100.3) - area.grid.left) * 256)
            .floor();
        final y = ((WeatherAreaGrid.tileY(5.4) - area.grid.top) * 256).floor();
        expect(
          rgba.getUint8((y * result.width + x) * 4 + 3),
          inInclusiveRange(47, 49),
        );
        expect(
          rgba.getUint8(3),
          0,
        ); // Outside the circular area, not colored rain.
        result.dispose();
        codec.dispose();
        await load(refresh: true);
        expect(calls, count * 2);
        now = now.add(const Duration(hours: 3));
        await load();
        expect(calls, count * 3);
      });
    },
  );

  testWidgets('failed downloads are not cached as dry weather', (tester) async {
    await tester.runAsync(() async {
      var calls = 0;
      final service = WeatherAreaService(
        client: MockClient((_) async {
          calls++;
          return http.Response('Unauthorized', 401);
        }),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          service.load(
            latitude: 5.4,
            longitude: 100.3,
            layer: WeatherMapLayer.rain,
            apiKey: 'test',
          ),
          throwsStateError,
        );
      }
      expect(calls, 2);
    });
  });
}
