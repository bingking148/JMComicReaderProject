import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'engine/client.dart';
import 'engine/data_root.dart';
import 'engine/host.dart';
import 'engine/models.dart';

class Session extends ChangeNotifier with WidgetsBindingObserver {
  EngineClient? engine;
  Process? _process;
  Settings settings = const Settings();
  List<Job> jobs = const [];
  bool booting = true;
  String? bootError;
  Timer? _poll;

  Future<void> boot() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final dir = await resolveDataDir();
      final endpoint = await EngineHost.start(dir);
      _process = endpoint.process;
      engine = EngineClient(base: endpoint.base, token: endpoint.token);
      settings = await engine!.settings();
      bootError = null;
      if (settings.ageAccepted) {
        await refreshJobs();
        _ensurePoll();
      }
    } catch (err) {
      bootError = err.toString();
    } finally {
      booting = false;
      notifyListeners();
    }
  }

  EngineClient get api {
    final current = engine;
    if (current == null) throw EngineException('引擎还没有准备好');
    return current;
  }

  Future<void> acceptAge() async {
    settings = await api.updateSettings(settings.copyWith(ageAccepted: true));
    notifyListeners();
    await refreshJobs();
    _ensurePoll();
  }

  Future<void> saveSettings(Settings next) async {
    settings = await api.updateSettings(next);
    notifyListeners();
  }

  void adopt(Settings next) {
    settings = next;
    notifyListeners();
  }

  /// Points later launches at [path]. When [move] is true the current files
  /// are transferred and removed from the old directory. Otherwise the old
  /// directory is left as it is.
  Future<String> changeDataDirectory(String path, {required bool move}) async {
    final previous = settings.dataDir;
    DataRootChange change;
    try {
      change = await api.relocateData(path, move: move);
    } catch (err) {
      rethrow;
    }
    if (!change.restart) {
      if (change.error.isNotEmpty) throw EngineException(change.error);
      return previous;
    }
    final target = change.error.isEmpty || change.moved ? (change.newPath.isEmpty ? path : change.newPath) : previous;
    if (change.error.isEmpty || change.moved) {
      await writeDataPointer(target);
    }
    await _restart(target);
    if (change.error.isNotEmpty) throw EngineException(change.error);
    return target;
  }

  Future<void> _restart(String dataDir) async {
    _poll?.cancel();
    _poll = null;
    _process?.kill();
    _process = null;
    engine = null;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final endpoint = await EngineHost.start(dataDir);
    _process = endpoint.process;
    engine = EngineClient(base: endpoint.base, token: endpoint.token);
    settings = await engine!.settings();
    bootError = null;
    if (settings.ageAccepted) {
      await refreshJobs();
      _ensurePoll();
    }
    notifyListeners();
  }

  Future<void> refreshJobs() async {
    if (engine == null || !settings.ageAccepted) return;
    try {
      jobs = await api.downloads();
      notifyListeners();
    } catch (_) {}
  }

  void _ensurePoll() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 1200), (_) => refreshJobs());
  }

  Job? jobFor(int id) {
    for (final job in jobs) {
      if (job.albumId == id) return job;
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _process?.kill();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _process?.kill();
    super.dispose();
  }
}

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({required Session session, required super.child, super.key}) : super(notifier: session);

  static Session of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope 缺失');
    return scope!.notifier!;
  }
}
