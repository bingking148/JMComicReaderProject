import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'detail.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({required this.query, super.key});
  final String query;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final List<Summary> _items = [];
  String _sort = 'latest';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = reset;
      _more = !reset;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
      }
    });
    try {
      final session = SessionScope.of(context);
      final result = await session.api.search(widget.query, page: _page, sort: _sort);
      if (result.direct && result.items.length == 1 && mounted) {
        final id = result.items.first.id;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DetailPage(id: id)));
        return;
      }
      final enriched = await session.api.enrich(result.items.take(12).map((e) => e.id).toList());
      final merged = result.items.map((item) => enriched[item.id] ?? item).toList();
      if (_sort == 'favorites_desc') {
        merged.sort((a, b) => b.favorites.compareTo(a.favorites));
      } else if (_sort == 'favorites_asc') {
        merged.sort((a, b) => a.favorites.compareTo(b.favorites));
      }
      if (!mounted) return;
      setState(() {
        _items.addAll(merged);
        _total = result.total;
        _loading = false;
        _more = false;
      });
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.message;
        _loading = false;
        _more = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: InkColors.bg,
        foregroundColor: InkColors.paper,
        elevation: 0,
        title: Text(widget.query, style: const TextStyle(fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                _sortButton('最新', 'latest'),
                _sortButton('收藏多', 'favorites_desc'),
                _sortButton('收藏少', 'favorites_asc'),
                const Spacer(),
                Text(_total > 0 ? '$_total 条' : '', style: const TextStyle(color: InkColors.mute, fontSize: 12)),
              ],
            ),
          ),
          const Divider(height: 1, color: InkColors.line),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _sortButton(String label, String value) {
    final selected = _sort == value;
    return TextButton(
      onPressed: selected
          ? null
          : () {
              _sort = value;
              _load(reset: true);
            },
      child: Text(label, style: TextStyle(color: selected ? InkColors.cinnabar : InkColors.dim)),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: ProgressRule());
    if (_error != null) {
      return QuietMessage(title: '没有检索到', detail: _error);
    }
    if (_items.isEmpty) return const QuietMessage(title: '没有结果');
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 300,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 22,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _items[index];
                    return ComicTile(
                      summary: item,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(id: item.id))),
                    );
                  },
                  childCount: _items.length,
                ),
              ),
            ),
            if (_items.length < _total)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: TextButton(
                      onPressed: _more
                          ? null
                          : () {
                              _page += 1;
                              _load(reset: false);
                            },
                      child: Text(_more ? '正在取下一页' : '下一页'),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
