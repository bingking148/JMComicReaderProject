import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the directory that holds comics, covers, and the library database.
///
/// Android and iOS always use the private application directory.
/// Desktop reads a small pointer file when one exists, so an installer or the
/// settings page can put bulky data on another drive. With no pointer, the
/// historical application-support directory is used.
Future<String> resolveDataDir() async {
  final fallback = (await getApplicationSupportDirectory()).path;
  if (Platform.isAndroid || Platform.isIOS) return fallback;
  final saved = await _read(userPointerFile());
  if (saved != null) return saved;
  if (Platform.isWindows) {
    final besideExe = await _read(File(p.join(p.dirname(Platform.resolvedExecutable), 'data_root.txt')));
    if (besideExe != null) return besideExe;
  }
  return fallback;
}

/// Records [path] as the library directory for later launches.
/// This does not move or delete any files.
Future<void> writeDataPointer(String path) async {
  final file = userPointerFile();
  await file.parent.create(recursive: true);
  final cleaned = p.normalize(path.trim());
  await file.writeAsString('$cleaned\n', flush: true);
}

File userPointerFile() {
  final override = Platform.environment['JM_DATA_POINTER'];
  if (override != null && override.trim().isNotEmpty) {
    return File(override.trim());
  }
  if (Platform.isWindows) {
    final base = Platform.environment['APPDATA'] ?? p.join(Platform.environment['USERPROFILE'] ?? '', 'AppData', 'Roaming');
    return File(p.join(base, 'JMComicReader', 'data_root.txt'));
  }
  if (Platform.isMacOS) {
    return File(p.join(homeOrEmpty(), 'Library', 'Preferences', 'JMComicReader', 'data_root.txt'));
  }
  final config = Platform.environment['XDG_CONFIG_HOME'];
  final base = (config != null && config.isNotEmpty) ? config : p.join(homeOrEmpty(), '.config');
  return File(p.join(base, 'JMComicReader', 'data_root.txt'));
}

String homeOrEmpty() => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

String? parsePointer(String text) {
  final line = text.split(RegExp(r'\r?\n')).first.trim();
  if (line.isEmpty || p.isRelative(line)) return null;
  return p.normalize(line);
}

Future<String?> _read(File file) async {
  if (!await file.exists()) return null;
  return parsePointer(await file.readAsString());
}
