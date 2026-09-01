import 'package:flutter_test/flutter_test.dart';
import 'package:hiker_circle/core/widgets/worldwide_region_picker.dart';

void main() {
  test(
    'normalizes Malaysian state aliases without network geocoding',
    () async {
      final penang = await WorldwideRegionCatalog.normalize(
        country: '',
        state: 'Pulau Pinang',
      );
      final melaka = await WorldwideRegionCatalog.normalize(
        country: 'MY',
        state: 'Melaka',
      );
      final selangor = await WorldwideRegionCatalog.normalize(
        country: 'Malaysia',
        state: 'Selangor',
      );

      expect(penang?.country, 'Malaysia');
      expect(penang?.state, 'Penang');
      expect(penang?.stateCode, '07');
      expect(melaka?.state, 'Malacca');
      expect(selangor?.state, 'Selangor');
    },
  );
}
