import 'package:flutter/material.dart';

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
  List<String> _recent = const [];
  List<Comic> _continue = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = SessionScope.of(context);
    try {
      final recent = await session.api.recentSearches();
      final library = await session.api.library();
      library.sort((a, b) => b.lastRead.compareTo(a.lastRead));
      if (!mounted) return;
      setState(() {
        _recent = recent;
        _continue = library.where((comic) => comic.lastRead.isNotEmpty).take(8).toList();
      });
    } catch (_) {}
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

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        children: [
          const Wordmark(),
          const SizedBox(height: 8),
          const Text('本地阅读。搜索、下载和翻页都发生在这台设备上。', style: TextStyle(color: InkColors.mute)),
          const SizedBox(height: 28),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(hintText: '关键词，或 JM 编号'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => _submit(_query.text), child: const Text('检索')),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionLabel('最近'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in _recent)
                  TextButton(onPressed: () => _submit(item), child: Text(item)),
              ],
            ),
          ],
          if (_continue.isNotEmpty) ...[
            const SizedBox(height: 28),
            const SectionLabel('接着读'),
            const SizedBox(height: 12),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _continue.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final comic = _continue[index];
                  return SizedBox(
                    width: 120,
                    child: ComicTile(
                      summary: Summary(id: comic.id, title: comic.title, author: comic.author),
                      coverPath: comic.coverPath,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: comic.id))),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
