import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../reader/reader_screen.dart';
import '../session.dart';
import '../theme.dart';
import 'detail.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Comic> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final items = await SessionScope.of(context).api.library();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _loading = false;
      });
    }
  }

  Future<void> _delete(Comic comic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从书架移除'),
        content: Text('删除《${comic.title}》的本地文件。这个操作不能撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('留下')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await SessionScope.of(context).api.deleteComic(comic.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
            child: Row(
              children: [
                const Text('书架', style: TextStyle(fontSize: 26)),
                const Spacer(),
                Text('${_items.length}', style: const TextStyle(color: InkColors.mute)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: InkColors.dim, size: 18)),
              ],
            ),
          ),
          const Divider(height: 1, color: InkColors.line),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: ProgressRule(value: 0));
    if (_error != null) return QuietMessage(title: '书架没有打开', detail: _error);
    if (_items.isEmpty) {
      return const QuietMessage(title: '书架还是空的', detail: '下载完成后，漫画会留在这台设备上。');
    }
    final bytes = _items.fold<int>(0, (sum, comic) => sum + comic.fileSize);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('占用 ${formatBytes(bytes)}', style: const TextStyle(color: InkColors.mute, fontSize: 12)),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(22),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 310,
              crossAxisSpacing: 18,
              mainAxisSpacing: 20,
            ),
            itemCount: _items.length,
            itemBuilder: (context, index) {
              final comic = _items[index];
              return GestureDetector(
                onLongPress: () => _delete(comic),
                child: Stack(
                  children: [
                    ComicTile(
                      summary: Summary(id: comic.id, title: comic.title, author: comic.author),
                      coverPath: comic.coverPath,
                      onTap: () {
                        if (comic.pages > 0) {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ReaderScreen(albumId: comic.id, initialChapterId: comic.chapterId),
                          ));
                        } else {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: comic.id)));
                        }
                      },
                    ),
                    if (comic.status != 'complete')
                      const Positioned(
                        left: 6,
                        top: 6,
                        child: TagChip('未完成'),
                      ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        onPressed: () => _delete(comic),
                        icon: const Icon(Icons.close, size: 16, color: InkColors.mute),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
