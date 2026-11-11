import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic_reader/reader/policy.dart';

void main() {
  test('mode names round-trip', () {
    expect(readModeFromName(readModeName(ReadMode.spread)), ReadMode.spread);
    expect(fitModeFromName('contain'), FitMode.contain);
  });
}
