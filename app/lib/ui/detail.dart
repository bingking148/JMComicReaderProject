import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../reader/reader_screen.dart';
import '../session.dart';
import '../theme.dart';
import 'widgets.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({required this.id, super.key});
  final int id;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Album? _album;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final album = await SessionScope.of(context).api.album(widget.id);
      if (!mounted) return;
      setState(() {
        _album = album;
        _loading = false;
      });
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _loading = false;
      });
    }
  }

  Future<void> _download({bool restart = false}) async {
    final session = SessionScope.of(context);
    try {
      await session.api.startDownload(widget.id, restart: restart);
      await session.refreshJobs();
    } on EngineException catch (err) {
      if (!mounted) return;
      if (err.message.contains('已经在书架')) {
        final again = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('已经在书架上'),
            content: const Text('可以重新下载，已有的阅读进度会保留。'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('重新下载')),
            ],
          ),
        );
        if (again == true) await _download(restart: true);
        return;
      }
      setState(() => _error = err.message);
    }
  }

  void _openReader([int? chapterId]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(albumId: widget.id, initialChapterId: chapterId?.toString()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final job = session.jobFor(widget.id);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: InkColors.bg,
        foregroundColor: InkColors.paper,
        elevation: 0,
        title: const Text('详情', style: TextStyle(fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: ProgressRule())
          : _error != null && _album == null
              ? QuietMessage(title: '打不开这本', detail: _error)
              : _content(session, job),
    );
  }

  Widget _content(Session session, Job? job) {
    final album = _album!;
    final summary = album.summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final info = _info(summary, album, job);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 240, height: 340, child: CoverImage(id: summary.id)),
                  const SizedBox(width: 28),
                  Expanded(child: info),
                ],
              )
            else ...[
              Center(child: SizedBox(width: 200, height: 280, child: CoverImage(id: summary.id))),
              const SizedBox(height: 20),
              info,
            ],
          ],
        );
      },
    );
  }

  Widget _info(Summary summary, Album album, Job? job) {
    final busy = job != null && job.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary.title, style: const TextStyle(fontSize: 26, height: 1.25)),
        const SizedBox(height: 8),
        Text('${summary.author}  ·  JM${summary.id}', style: const TextStyle(color: InkColors.dim)),
        if (summary.favorites > 0) ...[
          const SizedBox(height: 6),
          Text('${compactCount(summary.favorites)} 收藏', style: const TextStyle(color: InkColors.brass, fontSize: 13)),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final tag in summary.tags.take(16)) TagChip(tag)]),
        if (summary.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(summary.description, style: const TextStyle(height: 1.5, color: InkColors.dim)),
        ],
        if (album.works.isNotEmpty || album.actors.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            [
              if (album.works.isNotEmpty) '作品 ${album.works.join('、')}',
              if (album.actors.isNotEmpty) '角色 ${album.actors.join('、')}',
            ].join('   '),
            style: const TextStyle(color: InkColors.mute, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
        if (busy) ...[
          Text(job.message, style: const TextStyle(color: InkColors.dim)),
          const SizedBox(height: 8),
          ProgressRule(value: job.track),
          TextButton(onPressed: () => SessionScope.of(context).api.pause(summary.id), child: const Text('暂停')),
        ] else
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: _download, child: Text(summary.downloaded ? '已在书架' : '下载')),
              if (summary.downloaded || summary.partial)
                TextButton(onPressed: () => _openReader(), child: const Text('阅读')),
            ],
          ),
        const SizedBox(height: 22),
        const SectionLabel('章节'),
        const SizedBox(height: 8),
        for (final chapter in album.chapters)
          InkWell(
            onTap: summary.downloaded || summary.partial ? () => _openReader(chapter.id) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Text(chapter.name)),
                  Text(
                    chapter.pages > 0 ? '${chapter.pages} 页' : '第${chapter.sort}话',
                    style: const TextStyle(color: InkColors.mute, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        if (album.related.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionLabel('相关'),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: album.related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = album.related[index];
                return SizedBox(
                  width: 120,
                  child: ComicTile(
                    summary: item,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: item.id))),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
