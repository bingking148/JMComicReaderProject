import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _api;
  late final TextEditingController _images;
  int _cache = 0;
  int? _concurrency;
  String? _note;
  late final TextEditingController _dataDir;
  bool _movingData = false;

  @override
  void initState() {
    super.initState();
    _api = TextEditingController();
    _images = TextEditingController();
    _dataDir = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = SessionScope.of(context).settings;
      _api.text = settings.apiDomains.join('\n');
      _images.text = settings.imageDomains.join('\n');
      _dataDir.text = settings.dataDir;
      _refreshCache();
    });
  }

  @override
  void dispose() {
    _api.dispose();
    _images.dispose();
    _dataDir.dispose();
    super.dispose();
  }

  bool get _canChooseDataDir => !Platform.isAndroid && !Platform.isIOS;

  Future<void> _changeDataDir(String current) async {
    final next = _dataDir.text.trim();
    if (next.isEmpty || next == current) {
      setState(() => _note = '请填写一个新的数据目录');
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更改漫画数据目录'),
        content: Text(
          '当前：$current\n新目录：$next\n\n'
          '移动数据：漫画会搬到新目录，旧目录不再保存这些文件。\n'
          '只改路径：旧目录原样留下，应用改为使用新目录。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, 'switch'), child: const Text('只改路径')),
          TextButton(onPressed: () => Navigator.pop(context, 'move'), child: const Text('移动数据')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _movingData = true);
    try {
      final saved = await SessionScope.of(context).changeDataDirectory(next, move: choice == 'move');
      if (!mounted) return;
      _dataDir.text = saved;
      setState(() => _note = choice == 'move' ? '数据已移动到新目录' : '已改用新目录，旧目录仍保留');
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _note = err.message);
    } finally {
      if (mounted) setState(() => _movingData = false);
    }
  }

  List<String> _lines(TextEditingController controller) {
    return controller.text.split(RegExp(r'\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _save(Settings next) async {
    try {
      await SessionScope.of(context).saveSettings(next);
      if (!mounted) return;
      setState(() => _note = '已保存');
    } on EngineException catch (err) {
      setState(() => _note = err.message);
    }
  }

  Future<void> _refreshCache() async {
    try {
      final bytes = await SessionScope.of(context).api.cacheBytes();
      if (!mounted) return;
      setState(() => _cache = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final settings = session.settings;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 48),
        children: [
          const Text('设置', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 18),
          const SectionLabel('漫画数据目录'),
          const SizedBox(height: 6),
          const Text(
            '封面、下载的漫画和书架数据库都在这里。它和程序安装位置不是同一个文件夹。',
            style: TextStyle(color: InkColors.mute, height: 1.4),
          ),
          const SizedBox(height: 8),
          if (_canChooseDataDir)
            TextField(
              controller: _dataDir,
              decoration: const InputDecoration(hintText: r'D:\JMComicReader'),
            )
          else
            SelectableText(settings.dataDir, style: const TextStyle(color: InkColors.dim)),
          if (_canChooseDataDir)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _movingData ? null : () => _changeDataDir(settings.dataDir),
                child: Text(_movingData ? '正在处理…' : '更改数据目录'),
              ),
            ),
          const SizedBox(height: 22),
          const SectionLabel('API 域名'),
          TextField(controller: _api, maxLines: 5, decoration: const InputDecoration(hintText: '每行一个')),
          const SizedBox(height: 16),
          const SectionLabel('图片域名'),
          TextField(controller: _images, maxLines: 5),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启动时自动更新 API 域名'),
            value: settings.autoUpdateDomains,
            activeThumbColor: InkColors.cinnabar,
            onChanged: (value) => _save(settings.copyWith(
              apiDomains: _lines(_api),
              imageDomains: _lines(_images),
              autoUpdateDomains: value,
            )),
          ),
          Row(
            children: [
              const Text('同时下载'),
              Expanded(
                child: Slider(
                  value: (_concurrency ?? settings.concurrency).toDouble(),
                  min: 1,
                  max: 16,
                  divisions: 15,
                  label: '${_concurrency ?? settings.concurrency}',
                  onChanged: (value) => setState(() => _concurrency = value.round()),
                  onChangeEnd: (value) async {
                    await _save(settings.copyWith(
                      apiDomains: _lines(_api),
                      imageDomains: _lines(_images),
                      concurrency: value.round(),
                    ));
                    if (mounted) setState(() => _concurrency = null);
                  },
                ),
              ),
              Text('${settings.concurrency}'),
            ],
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => _save(settings.copyWith(apiDomains: _lines(_api), imageDomains: _lines(_images))),
                child: const Text('保存域名'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final next = await session.api.refreshDomains();
                    session.adopt(next);
                    _api.text = next.apiDomains.join('\n');
                    if (!mounted) return;
                    setState(() => _note = '域名已更新');
                  } on EngineException catch (err) {
                    setState(() => _note = err.message);
                  }
                },
                child: const Text('立即更新域名'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SectionLabel('缓存'),
          const SizedBox(height: 8),
          Text('封面缓存 ${formatBytes(_cache)}', style: const TextStyle(color: InkColors.dim)),
          Wrap(
            children: [
              TextButton(
                onPressed: () async {
                  await session.api.clearCache();
                  await _refreshCache();
                  if (mounted) setState(() => _note = '封面缓存已清理');
                },
                child: const Text('清理封面缓存'),
              ),
              TextButton(
                onPressed: () async {
                  final n = await session.api.rescan();
                  if (mounted) setState(() => _note = '重新扫描到 $n 本');
                },
                child: const Text('重新扫描书架'),
              ),
            ],
          ),
          if (_note != null) Text(_note!, style: const TextStyle(color: InkColors.brass)),
          const SizedBox(height: 28),
          const SectionLabel('关于'),
          const SizedBox(height: 8),
          Text('JMComicReader ${settings.appVersion.isEmpty ? '2.0.0' : settings.appVersion}', style: const TextStyle(color: InkColors.dim)),
          const SizedBox(height: 8),
          const Text(
            '本应用仅供学习交流。漫画来自网络，程序不会把内容上传到任何服务器。请遵守所在地法律，勿用于非法用途。阅读前需确认已年满 18 岁。',
            style: TextStyle(color: InkColors.mute, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text('MIT License', style: TextStyle(color: InkColors.mute, fontSize: 12)),
        ],
      ),
    );
  }
}
