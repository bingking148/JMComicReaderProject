import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic_reader/engine/models.dart';
import 'package:jm_comic_reader/reader/policy.dart';

void main() {
  test('mode names round-trip', () {
    expect(readModeFromName(readModeName(ReadMode.spread)), ReadMode.spread);
    expect(fitModeFromName('contain'), FitMode.contain);
  });

  test('a canceled download with no finished pages does not stay indeterminate', () {
    const canceled = Job(
      albumId: 1,
      title: '国漫世界',
      status: 'canceled',
      done: 0,
      total: 953,
      message: '已取消',
    );
    expect(canceled.active, isFalse);
    expect(canceled.track, 0);

    const preparing = Job(albumId: 1, title: '国漫世界', status: 'running', done: 0, total: 0, message: '正在准备');
    expect(preparing.track, isNull);
  });
}
