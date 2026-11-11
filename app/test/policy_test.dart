import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic_reader/engine/models.dart';
import 'package:jm_comic_reader/reader/policy.dart';

void main() {
  test('very tall pages use a continuous strip', () {
    expect(resolveSmart(aspect: 3.4, width: 1400, height: 900), ReadMode.strip);
    expect(resolveSmart(aspect: 2.4, width: 390, height: 844), ReadMode.strip);
  });

  test('a phone portrait page stays single', () {
    expect(resolveSmart(aspect: 1.4, width: 390, height: 844), ReadMode.single);
  });

  test('tablet and desktop landscape use a spread for normal pages', () {
    expect(resolveSmart(aspect: 1.35, width: 1200, height: 800), ReadMode.spread);
  });

  test('a short landscape phone does not force a spread', () {
    expect(resolveSmart(aspect: 1.4, width: 800, height: 360), ReadMode.single);
  });

  test('JM ids accept a bare number or a JM prefix', () {
    expect(parseJmId('438516'), 438516);
    expect(parseJmId('JM438516'), 438516);
    expect(parseJmId('jm12'), 12);
    expect(parseJmId('mana'), isNull);
  });
}
