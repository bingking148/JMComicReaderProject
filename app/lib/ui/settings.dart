import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final TextEditingController _dataDir;
  int? _concurrency;
  String? _note;
  bool _movingData = false;
  bool _busy = false;
  StorageUse _storage = const StorageUse();

  static const _repo = 'https://github.com/bingking148/JMComicReaderProject';
  static const _issues = 'https://github.com/bingking148/JMComicReaderProject/issues';
  static const _releases = 'https://github.com/bingking148/JMComicReaderProject/releases';

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
      _refreshStorage();
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

  List<String> _lines(TextEditingController controller) {
    return controller.text.split(RegExp(r'\s+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _save(Settings next) async {
    try {
      await SessionScope.of(context).saveSettings(next);
      if (!mounted) return;
      setState(() => _note = '已保存');
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _note = err.message);
    }
  }

  Future<void> _refreshStorage() async {
    try {
      final usage = await SessionScope.of(context).api.storage();
      if (!mounted) return;
      setState(() => _storage = usage);
    } catch (_) {}
  }

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
      await _refreshStorage();
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _note = err.message);
    } finally {
      if (mounted) setState(() => _movingData = false);
    }
  }

  Future<void> _reveal(String path) async {
    if (path.isEmpty) {
      setState(() => _note = '目录还不存在');
      return;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
      return;
    }
    var opened = false;
    if (Platform.isAndroid) {
      try {
        opened = await const MethodChannel('jmcomic/engine').invokeMethod<bool>('reveal', {'path': path}) ?? false;
      } catch (_) {}
    }
    if (!mounted || opened) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('漫画目录'),
        content: SelectableText(path),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('复制路径'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _import(String? path) async {
    final selected = path?.trim() ?? '';
    if (selected.isEmpty) return;
    final api = SessionScope.of(context).api;
    final kind = await FileSystemEntity.type(selected);
    if (!mounted) return;
    if (kind == FileSystemEntityType.notFound) {
      setState(() => _note = '选中的位置无法读取。可以改选 zip 或 cbz。');
      return;
    }
    setState(() => _busy = true);
    try {
      final report = await api.importPath(selected);
      if (!mounted) return;
      final detail = report.lines.where((line) => line.trim().isNotEmpty).take(4).join('\n');
      setState(() => _note = detail.isEmpty ? report.summary : '${report.summary}\n$detail');
      await _refreshStorage();
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _note = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择漫画文件夹');
    if (!mounted) return;
    await _import(path);
  }

  Future<void> _pickArchive() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择 zip 或 cbz',
      type: FileType.custom,
      allowedExtensions: const ['zip', 'cbz'],
    );
    if (!mounted || files.isEmpty) return;
    await _import(files.first.path);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final settings = session.settings;
    final comicsDir = _storage.comicsDir.isNotEmpty ? _storage.comicsDir : settings.dataDir;
    final version = settings.productVersion.isEmpty ? '2.0.0' : settings.productVersion;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 48),
        children: [
          const Text('设置', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 18),
          const SectionLabel('漫画目录'),
          const SizedBox(height: 6),
          const Text(
            '下载的漫画在这个文件夹里。它和程序安装位置不是同一个地方。',
            style: TextStyle(color: InkColors.mute, height: 1.4),
          ),
          const SizedBox(height: 8),
          SelectableText(comicsDir, style: const TextStyle(color: InkColors.dim, height: 1.4)),
          Wrap(
            children: [
              TextButton(onPressed: () => _reveal(comicsDir), child: Text(_canChooseDataDir ? '打开文件夹' : '查看路径')),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: comicsDir));
                  if (mounted) setState(() => _note = '路径已复制');
                },
                child: const Text('复制路径'),
              ),
            ],
          ),
          if (_canChooseDataDir) ...[
            const SizedBox(height: 8),
            const Text('数据目录包含书架数据库和上面的漫画文件夹。', style: TextStyle(color: InkColors.mute, height: 1.4)),
            const SizedBox(height: 8),
            TextField(controller: _dataDir, decoration: const InputDecoration(hintText: r'D:\JMComicReader')),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _movingData ? null : () => _changeDataDir(settings.dataDir),
                child: Text(_movingData ? '正在处理…' : '更改数据目录'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            '导入认 {编号}_{标题} 目录，也认现在的 comics 目录，以及同样结构的 zip / cbz。已经下完的书不会被覆盖。',
            style: TextStyle(color: InkColors.mute, height: 1.4),
          ),
          Wrap(
            children: [
              TextButton(onPressed: _busy ? null : _pickFolder, child: const Text('导入文件夹')),
              TextButton(onPressed: _busy ? null : _pickArchive, child: const Text('导入 zip / cbz')),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final n = await session.api.rescan();
                          if (mounted) setState(() => _note = '书架里有 $n 本');
                          await _refreshStorage();
                        } on EngineException catch (err) {
                          if (mounted) setState(() => _note = err.message);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('重新扫描'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('空间'),
          const SizedBox(height: 8),
          Text(
            '漫画 ${formatBytes(_storage.libraryBytes)}    封面缓存 ${formatBytes(_storage.cacheBytes)}',
            style: const TextStyle(color: InkColors.dim),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清理封面缓存'),
                    content: const Text('只删除搜索和详情用过的封面。已下载的漫画会留下。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('留下')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('清理')),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                await session.api.clearCache();
                await _refreshStorage();
                if (mounted) setState(() => _note = '封面缓存已清理');
              },
              child: const Text('清理封面缓存'),
            ),
          ),
          const SizedBox(height: 12),
          const SectionLabel('下载'),
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
          const SizedBox(height: 8),
          const SectionLabel('阅读'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              _mode('自动', 'smart', settings),
              _mode('单页', 'single', settings),
              _mode('跨页', 'spread', settings),
              _mode('长条', 'strip', settings),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('阅读时保持屏幕常亮'),
            value: settings.keepScreenOn,
            activeThumbColor: InkColors.cinnabar,
            onChanged: (value) => _save(settings.copyWith(
              apiDomains: _lines(_api),
              imageDomains: _lines(_images),
              keepScreenOn: value,
              keepAwake: value ? 'on' : 'off',
            )),
          ),
          const SizedBox(height: 8),
          const SectionLabel('连接'),
          const SizedBox(height: 8),
          const Text('API 域名', style: TextStyle(color: InkColors.mute, fontSize: 12)),
          TextField(controller: _api, maxLines: 4, decoration: const InputDecoration(hintText: '每行一个')),
          const SizedBox(height: 12),
          const Text('图片域名', style: TextStyle(color: InkColors.mute, fontSize: 12)),
          TextField(controller: _images, maxLines: 4),
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
          Wrap(
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
          if (_note != null) ...[
            const SizedBox(height: 8),
            Text(_note!, style: const TextStyle(color: InkColors.brass, height: 1.4)),
          ],
          const SizedBox(height: 28),
          const SectionLabel('关于'),
          const SizedBox(height: 8),
          Text('JMComicReader $version', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          const Text('开源项目', style: TextStyle(color: InkColors.mute, fontSize: 12)),
          const SizedBox(height: 8),
          const Text(
            '本地 JM 漫画阅读器。搜索、下载和阅读都在这台设备上完成。',
            style: TextStyle(color: InkColors.dim, height: 1.45),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _open(_repo), child: const Text('在 GitHub 上标星')),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _open(_repo),
              child: const Text('github.com/bingking148/JMComicReaderProject'),
            ),
          ),
          Wrap(
            children: [
              TextButton(onPressed: () => _open(_issues), child: const Text('问题')),
              TextButton(onPressed: () => _open(_releases), child: const Text('发布')),
              TextButton(onPressed: _showLicense, child: const Text('MIT 许可证')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '本应用仅供学习交流。漫画来自网络，程序不会把内容上传到任何服务器。请遵守所在地法律，勿用于非法用途。阅读前需确认已年满 18 岁。',
            style: TextStyle(color: InkColors.mute, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _showLicense() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('MIT 许可证'),
        content: const SizedBox(
          width: 420,
          child: SingleChildScrollView(child: Text(_license, style: TextStyle(height: 1.45, fontSize: 13))),
        ),
        actions: [
          TextButton(onPressed: () => _open('$_repo/blob/main/LICENSE'), child: const Text('在 GitHub 打开')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Widget _mode(String label, String value, Settings settings) {
    final selected = settings.readerMode == value;
    return TextButton(
      onPressed: selected
          ? null
          : () => _save(settings.copyWith(
                apiDomains: _lines(_api),
                imageDomains: _lines(_images),
                readerMode: value,
              )),
      child: Text(label, style: TextStyle(color: selected ? InkColors.cinnabar : InkColors.dim)),
    );
  }
}

const _license = '''
MIT License

Copyright (c) 2025 Your Name

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';
