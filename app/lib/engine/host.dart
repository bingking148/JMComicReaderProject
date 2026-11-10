import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'client.dart';

class EngineEndpoint {
  EngineEndpoint({required this.port, required this.token, this.process});
  final int port;
  final String token;
  final Process? process;
  String get base => 'http://127.0.0.1:$port';
}

class EngineHost {
  static const _channel = MethodChannel('jmcomic/engine');

  static Future<EngineEndpoint> start(String dataDir) async {
    if (Platform.isAndroid) {
      final port = await _channel.invokeMethod<int>('start', {'dataDir': dataDir});
      if (port == null || port <= 0) {
        throw EngineException('Android 引擎没有返回端口');
      }
      final token = (await File(p.join(dataDir, 'engine.token')).readAsString()).trim();
      return EngineEndpoint(port: port, token: token);
    }
    if (Platform.isIOS) {
      try {
        final port = await _channel.invokeMethod<int>('start', {'dataDir': dataDir});
        if (port != null && port > 0) {
          final token = (await File(p.join(dataDir, 'engine.token')).readAsString()).trim();
          return EngineEndpoint(port: port, token: token);
        }
      } on PlatformException catch (err) {
        throw EngineException(err.message ?? 'iOS 引擎尚未链接');
      }
    }
    return _startProcess(dataDir);
  }

  static Future<EngineEndpoint> _startProcess(String dataDir) async {
    final binary = findEngineBinary();
    if (binary == null) {
      throw EngineException(
        '找不到 Go 引擎。请在仓库根目录运行 scripts/build-engine.sh，'
        '或设置 JM_ENGINE 指向 jmengine 可执行文件。\n已查找：\n${candidateBinaries().join('\n')}',
      );
    }
    final process = await Process.start(binary, ['-data', dataDir]);
    final ready = Completer<EngineEndpoint>();
    final errors = StringBuffer();
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (!line.startsWith('READY ') || ready.isCompleted) return;
      final parts = line.split(' ');
      if (parts.length < 3) return;
      final port = int.tryParse(parts[1]);
      if (port == null) return;
      ready.complete(EngineEndpoint(port: port, token: parts.sublist(2).join(' '), process: process));
    });
    process.stderr.transform(utf8.decoder).listen(errors.write);
    try {
      return await ready.future.timeout(const Duration(seconds: 25));
    } catch (_) {
      process.kill();
      throw EngineException('引擎没有在预期时间内启动。\n$errors');
    }
  }

  static List<String> candidateBinaries() {
    final name = Platform.isWindows ? 'jmengine.exe' : 'jmengine';
    final env = Platform.environment['JM_ENGINE'];
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return [
      if (env != null && env.isNotEmpty) env,
      p.join(exeDir, name),
      p.join(exeDir, 'bin', name),
      p.join(Directory.current.path, 'bin', name),
      p.join(Directory.current.path, 'app', 'bin', name),
    ];
  }

  static String? findEngineBinary() {
    for (final candidate in candidateBinaries()) {
      final file = File(candidate);
      if (file.existsSync()) return file.path;
    }
    return null;
  }
}
