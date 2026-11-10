import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'engine/client.dart';
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
      final dir = await getApplicationSupportDirectory();
      final endpoint = await EngineHost.start(dir.path);
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
