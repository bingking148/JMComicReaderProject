import 'package:flutter/material.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'detail.dart';
import 'widgets.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    this.query = '',
    this.title = '',
    this.order = 'mr',
    this.time = 'a',
    this.category = '',
    super.key,
  });

  final String query;
  final String title;
  final String order;
  final String time;
  final String category;

  bool get browsing => category.isNotEmpty;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final List<Summary> _items = [];
  late String _order;
  late String _time;
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _time = widget.time;
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
      final result = widget.browsing
          ? await session.api.browse(category: widget.category, page: _page, order: _order, time: _time)
          : await session.api.search(widget.query, page: _page, order: _order, time: _time);
      if (!widget.browsing && result.direct && result.items.length == 1 && mounted) {
        final id = result.items.first.id;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DetailPage(id: id)));
        return;
      }
      final enriched = await session.api.enrich(result.items.take(12).map((e) => e.id).toList());
      final merged = result.items.map((item) => enriched[item.id] ?? item).toList();
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
        title: Text(widget.title.isNotEmpty ? widget.title : widget.query, style: const TextStyle(fontSize: 18)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                runSpacing: 0,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('排序', style: TextStyle(color: InkColors.mute, fontSize: 12)),
                  _choice('最新', 'mr', _order, (value) => _order = value),
                  _choice('观看', 'mv', _order, (value) => _order = value),
                  _choice('图片', 'mp', _order, (value) => _order = value),
                  _choice('收藏', 'tf', _order, (value) => _order = value),
                  const SizedBox(width: 12),
                  const Text('时间', style: TextStyle(color: InkColors.mute, fontSize: 12)),
                  _choice('今日', 't', _time, (value) => _time = value),
                  _choice('本周', 'w', _time, (value) => _time = value),
                  _choice('本月', 'm', _time, (value) => _time = value),
                  _choice('全部', 'a', _time, (value) => _time = value),
                  Text(_total > 0 ? '  $_total 条' : '', style: const TextStyle(color: InkColors.mute, fontSize: 12)),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: InkColors.line),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _choice(String label, String value, String selected, void Function(String value) assign) {
    final on = selected == value;
    return TextButton(
      onPressed: on
          ? null
          : () {
              assign(value);
              _load(reset: true);
            },
      child: Text(label, style: TextStyle(color: on ? InkColors.cinnabar : InkColors.dim)),
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
