import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'detail.dart';
import 'search.dart';
import 'widgets.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final _query = TextEditingController();
  DiscoverFeed? _feed;
  List<String> _recent = const [];
  List<Comic> _continue = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = SessionScope.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        session.api.discover(),
        session.api.recentSearches(),
        session.api.library(),
      ]);
      final library = results[2] as List<Comic>;
      library.sort((a, b) => b.lastRead.compareTo(a.lastRead));
      if (!mounted) return;
      setState(() {
        _feed = results[0] as DiscoverFeed;
        _recent = results[1] as List<String>;
        _continue = library.where((comic) => comic.lastRead.isNotEmpty).take(8).toList();
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

  void _submit(String raw) {
    final query = raw.trim();
    if (query.isEmpty) return;
    final id = parseJmId(query);
    if (id != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: id)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchPage(query: query)));
  }

  void _openShelf({required String title, required String order, required String time, String category = '0'}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SearchPage(title: title, order: order, time: time, category: category),
    ));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return SafeArea(
      child: RefreshIndicator(
        color: InkColors.cinnabar,
        backgroundColor: InkColors.raised,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
          children: [
            const Wordmark(),
            const SizedBox(height: 8),
            const Text('今日上架、收藏和分类都从站点目录来，阅读仍在这台设备上。', style: TextStyle(color: InkColors.mute)),
            const SizedBox(height: 22),
            TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(hintText: '关键词，或 JM 编号'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => _submit(_query.text), child: const Text('检索')),
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 28), child: ProgressRule(value: 0)),
            if (_error != null) ...[
              const SizedBox(height: 18),
              Text(_error!, style: const TextStyle(color: InkColors.cinnabar)),
            ],
            if (feed != null) ...[
              if (feed.keywords.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionLabel('推荐关键词'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final word in feed.keywords) TextButton(onPressed: () => _submit(word), child: Text(word)),
                  ],
                ),
              ],
              if (feed.categories.isNotEmpty) ...[
                const SizedBox(height: 8),
                const SectionLabel('分类'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final category in feed.categories)
                      if (category.id != '0')
                        TextButton(
                          onPressed: () => _openShelf(title: category.name, order: 'mr', time: 'a', category: category.id),
                          child: Text(category.name),
                        ),
                  ],
                ),
              ],
              _shelf(
                '每日最新',
                feed.latest,
                () => _openShelf(title: '每日最新', order: 'mr', time: 't'),
              ),
              _shelf(
                '收藏最多',
                feed.mostFavorited,
                () => _openShelf(title: '收藏最多', order: 'tf', time: 'a'),
              ),
            ],
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 8),
              const SectionLabel('最近搜索'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [for (final item in _recent) TextButton(onPressed: () => _submit(item), child: Text(item))],
              ),
            ],
            if (_continue.isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionLabel('接着读'),
              const SizedBox(height: 12),
              _comicRail(
                _continue
                    .map((comic) => Summary(id: comic.id, title: comic.title, author: comic.author))
                    .toList(),
                covers: {for (final comic in _continue) comic.id: comic.coverPath},
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _shelf(String title, List<Summary> items, VoidCallback onMore) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SectionLabel(title),
              const Spacer(),
              TextButton(onPressed: onMore, child: const Text('更多')),
            ],
          ),
          const SizedBox(height: 8),
          _comicRail(items),
        ],
      ),
    );
  }

  Widget _comicRail(List<Summary> items, {Map<int, String> covers = const {}}) {
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: 124,
            child: ComicTile(
              summary: item,
              coverPath: covers[item.id],
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: item.id))),
            ),
          );
        },
      ),
    );
  }
}
