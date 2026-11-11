import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic_reader/engine/data_root.dart';
import 'package:path/path.dart' as p;

void main() {
  test('pointer text keeps an absolute path and ignores a relative one', () {
    final absolute = p.separator == '\\' ? 'C:\\library' : '/library';
    expect(parsePointer('$absolute\r\n'), absolute);
    expect(parsePointer('comics'), isNull);
    expect(parsePointer('   \n'), isNull);
  });
}
