import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import 'policy.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.albumId, this.initialChapterId, super.key});
  final int albumId;
  final String? initialChapterId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  ReaderDoc? _doc;
  String? _error;
  int _chapter = 0;
  int _page = 0;
  double _offset = 0;
  ReadMode _choice = ReadMode.smart;
  FitMode _fit = FitMode.width;
  bool _rtl = false;
  bool _chrome = true;
  double? _aspect;
  Timer? _hide;
  Timer? _save;
  PageController? _pages;
  ScrollController? _scroll;
  BoxConstraints? _constraints;
  int _cacheSize = 0;
  int _cacheBytes = 0;

  ReaderChapter? get _current {
    final doc = _doc;
    if (doc == null || doc.chapters.isEmpty) return null;
    return doc.chapters[_chapter.clamp(0, doc.chapters.length - 1).toInt()];
  }

  @override
  void initState() {
    super.initState();
    final cache = PaintingBinding.instance.imageCache;
    _cacheSize = cache.maximumSize;
    _cacheBytes = cache.maximumSizeBytes;
    cache.maximumSize = 28;
    cache.maximumSizeBytes = 96 << 20;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      final doc = await SessionScope.of(context).api.reader(widget.albumId);
      if (!mounted) return;
      var index = doc.chapters.indexWhere((c) => c.id == (widget.initialChapterId?.isNotEmpty == true ? widget.initialChapterId : doc.chapterId));
      if (index < 0) index = 0;
      final sameChapter = doc.chapters.isNotEmpty && doc.chapters[index].id == doc.chapterId;
      setState(() {
        _doc = doc;
        _choice = readModeFromName(doc.mode);
        _fit = fitModeFromName(doc.fit);
        _rtl = doc.rtl;
        _chapter = index;
        _page = sameChapter ? math.max(0, doc.page - 1) : 0;
        _offset = sameChapter ? doc.offset : 0;
      });
      _bindControllers();
      _armChrome();
      _precache();
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    }
  }

  ReadMode _controllerMode() {
    if (_choice == ReadMode.strip || _choice == ReadMode.spread || _choice == ReadMode.single) {
      return _choice;
    }
    final box = _constraints;
    if (box == null || _aspect == null) return ReadMode.single;
    return resolveSmart(aspect: _aspect!, width: box.maxWidth, height: box.maxHeight);
  }

  void _bindControllers() {
    _pages?.dispose();
    _scroll?.dispose();
    final count = _current?.pages.length ?? 0;
    final mode = _controllerMode();
    final initial = mode == ReadMode.spread
        ? (count == 0 ? 0 : _page ~/ 2)
        : (count == 0 ? 0 : math.min(_page + 1, count + 1));
    _pages = PageController(initialPage: initial);
    _scroll = ScrollController();
    if (_offset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll?.hasClients == true) {
          final max = _scroll!.position.maxScrollExtent;
          _scroll!.jumpTo(_offset.clamp(0, max));
        }
      });
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _save?.cancel();
    _pages?.dispose();
    _scroll?.dispose();
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = _cacheSize;
    cache.maximumSizeBytes = _cacheBytes;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  ReadMode _effective(BoxConstraints constraints) {
    if (_choice != ReadMode.smart) return _choice;
    final aspect = _aspect;
    if (aspect == null) return ReadMode.single;
    return resolveSmart(aspect: aspect, width: constraints.maxWidth, height: constraints.maxHeight);
  }

  void _armChrome() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && _chrome) setState(() => _chrome = false);
    });
    SystemChrome.setEnabledSystemUIMode(_chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    if (_chrome) _armChrome();
  }

  void _rememberAspect(double aspect) {
    if (_aspect != null && (_aspect! - aspect).abs() < 0.05) return;
    if (_choice != ReadMode.smart && _aspect != null) return;
    final before = _controllerMode();
    setState(() => _aspect = aspect);
    if (_controllerMode() != before) _bindControllers();
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 420), () async {
      final chapter = _current;
      if (!mounted || chapter == null) return;
      final offset = _scroll?.hasClients == true ? _scroll!.offset : _offset;
      try {
        await SessionScope.of(context).api.saveProgress(widget.albumId, chapter.id, _page + 1, offset);
      } catch (_) {}
    });
  }

  void _precache() {
    final pages = _current?.pages ?? const <String>[];
    for (final delta in const [-1, 1, 2]) {
      final index = _page + delta;
      if (index < 0 || index >= pages.length) continue;
      precacheImage(FileImage(File(pages[index])), context);
    }
  }

  void _setPage(int page) {
    final count = _current?.pages.length ?? 0;
    if (count == 0) return;
    final next = page.clamp(0, count - 1).toInt();
    if (next == _page) return;
    setState(() => _page = next);
    _scheduleSave();
    _precache();
    _armChrome();
  }

  void _goChapter(int index, {int page = 0, double offset = 0}) {
    final doc = _doc;
    if (doc == null || index < 0 || index >= doc.chapters.length) return;
    setState(() {
      _chapter = index;
      _page = page.clamp(0, math.max(0, doc.chapters[index].pages.length - 1)).toInt();
      _offset = offset;
      _aspect = null;
    });
    _bindControllers();
    _scheduleSave();
    _precache();
  }

  void _turn(int delta) {
    final mode = _choice == ReadMode.strip || (_choice == ReadMode.smart && _aspect != null && _aspect! >= 2.15)
        ? ReadMode.strip
        : (_choice == ReadMode.spread ? ReadMode.spread : ReadMode.single);
    if (mode == ReadMode.strip) {
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      final target = scroll.offset + delta * scroll.position.viewportDimension * 0.86;
      scroll.animateTo(
        target.clamp(0, scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (mode == ReadMode.spread) {
      _turnSpread(delta);
      return;
    }
    final count = _current?.pages.length ?? 0;
    final next = _page + delta;
    if (next < 0) {
      _goChapter(_chapter - 1, page: 1 << 20);
      return;
    }
    if (next >= count) {
      _goChapter(_chapter + 1);
      return;
    }
    _pages?.animateToPage(next + 1, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  void _turnSpread(int delta) {
    final count = _current?.pages.length ?? 0;
    final spread = _page ~/ 2;
    final spreads = (count + 1) ~/ 2;
    final next = spread + delta;
    if (next < 0) {
      _goChapter(_chapter - 1, page: 1 << 20);
      return;
    }
    if (next >= spreads) {
      _goChapter(_chapter + 1);
      return;
    }
    _setPage(next * 2);
    _pages?.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  Future<void> _persistMode() async {
    final session = SessionScope.of(context);
    await session.saveSettings(session.settings.copyWith(
      readerMode: readModeName(_choice),
      fitMode: fitModeName(_fit),
      rtl: _rtl,
    ));
  }

  void _cycleMode() {
    const order = [ReadMode.smart, ReadMode.single, ReadMode.spread, ReadMode.strip];
    setState(() => _choice = order[(order.indexOf(_choice) + 1) % order.length]);
    _bindControllers();
    _persistMode();
  }

  void _cycleFit() {
    setState(() => _fit = _fit == FitMode.width ? FitMode.contain : FitMode.width);
    _persistMode();
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: InkColors.read,
      body: doc == null
          ? Center(child: Text(_error ?? '正在打开', style: const TextStyle(color: InkColors.dim)))
          : LayoutBuilder(
              builder: (context, constraints) {
                _constraints = constraints;
                final mode = _effective(constraints);
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(_rtl ? -1 : 1),
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(_rtl ? 1 : -1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _turn(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _turn(-1),
                    const SingleActivator(LogicalKeyboardKey.space): () => _turn(1),
                    const SingleActivator(LogicalKeyboardKey.keyM): _cycleMode,
                    const SingleActivator(LogicalKeyboardKey.keyF): _cycleFit,
                    const SingleActivator(LogicalKeyboardKey.escape): _toggleChrome,
                  },
                  child: Focus(
                    autofocus: true,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _viewport(mode, constraints)),
                        _bar(doc, mode, top: true),
                        _bar(doc, mode, top: false),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _viewport(ReadMode mode, BoxConstraints constraints) {
    final chapter = _current;
    if (chapter == null || chapter.pages.isEmpty) {
      return const Center(child: Text('这一章没有页面', style: TextStyle(color: InkColors.mute)));
    }
    if (mode == ReadMode.strip) return _strip(chapter, constraints);
    if (mode == ReadMode.spread) return _spread(chapter, constraints);
    return _single(chapter, constraints);
  }

  Widget _single(ReaderChapter chapter, BoxConstraints constraints) {
    final controller = _pages;
    if (controller == null) return const SizedBox.shrink();
    return PageView.builder(
      controller: controller,
      itemCount: chapter.pages.length + 2,
      onPageChanged: (index) {
        if (index == 0) {
          _goChapter(_chapter - 1, page: 1 << 20);
          return;
        }
        if (index == chapter.pages.length + 1) {
          _goChapter(_chapter + 1);
          return;
        }
        _setPage(index - 1);
      },
      itemBuilder: (context, index) {
        if (index == 0 || index == chapter.pages.length + 1) {
          return _sentinel(index == 0);
        }
        return ComicPage(
          path: chapter.pages[index - 1],
          fit: _fit,
          onAspect: index - 1 == 0 ? _rememberAspect : null,
          onTap: (details, size) => _handleTap(details.localPosition.dx, size.width),
        );
      },
    );
  }

  Widget _spread(ReaderChapter chapter, BoxConstraints constraints) {
    final controller = _pages ?? PageController(initialPage: _page ~/ 2);
    final spreads = (chapter.pages.length + 1) ~/ 2;
    return PageView.builder(
      controller: controller,
      itemCount: spreads,
      onPageChanged: (index) => _setPage(index * 2),
      itemBuilder: (context, index) {
        final left = index * 2;
        final right = left + 1;
        return Row(
          children: [
            Expanded(child: _spreadSide(chapter, _rtl ? right : left)),
            Container(width: 1, color: InkColors.line),
            Expanded(child: _spreadSide(chapter, _rtl ? left : right)),
          ],
        );
      },
    );
  }

  Widget _spreadSide(ReaderChapter chapter, int index) {
    if (index < 0 || index >= chapter.pages.length) return const ColoredBox(color: InkColors.read);
    return ComicPage(
      path: chapter.pages[index],
      fit: FitMode.contain,
      onAspect: index == 0 ? _rememberAspect : null,
      onTap: (details, size) => _handleTap(details.localPosition.dx, size.width),
    );
  }

  Widget _strip(ReaderChapter chapter, BoxConstraints constraints) {
    final scroll = _scroll;
    if (scroll == null) return const SizedBox.shrink();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          _offset = scroll.offset;
          _scheduleSave();
        }
        return false;
      },
      child: ListView.builder(
        controller: scroll,
        scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
        itemCount: chapter.pages.length + 1,
        itemBuilder: (context, index) {
          if (index == chapter.pages.length) return _sentinel(false);
          final width = math.min(constraints.maxWidth, 920.0);
          final dpr = MediaQuery.devicePixelRatioOf(context);
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: GestureDetector(
                onTapUp: (details) {
                  if ((details.localPosition.dx - width / 2).abs() < width * 0.22) _toggleChrome();
                },
                child: Image.file(
                  File(chapter.pages[index]),
                  width: width,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  cacheWidth: (width * dpr).clamp(1, 1800).round(),
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 180,
                    child: Center(child: Text('这一页无法显示', style: TextStyle(color: InkColors.mute))),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sentinel(bool previous) {
    final doc = _doc!;
    final has = previous ? _chapter > 0 : _chapter < doc.chapters.length - 1;
    final label = !has
        ? (previous ? '已经是第一章' : '已经读完')
        : (previous ? '上一章  ${doc.chapters[_chapter - 1].name}' : '下一章  ${doc.chapters[_chapter + 1].name}');
    return Center(
      child: TextButton(
        onPressed: !has ? null : () => _goChapter(previous ? _chapter - 1 : _chapter + 1, page: previous ? 1 << 20 : 0),
        child: Text(label, style: const TextStyle(color: InkColors.dim)),
      ),
    );
  }

  void _handleTap(double x, double width) {
    if (x < width * 0.28) {
      _turn(_rtl ? 1 : -1);
    } else if (x > width * 0.72) {
      _turn(_rtl ? -1 : 1);
    } else {
      _toggleChrome();
    }
  }

  Widget _bar(ReaderDoc doc, ReadMode mode, {required bool top}) {
    final chapter = _current;
    final count = chapter?.pages.length ?? 0;
    final child = top
        ? Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: InkColors.paper, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(chapter?.name ?? '', style: const TextStyle(color: InkColors.mute, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(onPressed: _cycleMode, child: Text(readModeLabel(_choice == ReadMode.smart ? mode : _choice))),
              TextButton(onPressed: () => _chapters(doc), child: const Text('章节')),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('${count == 0 ? 0 : _page + 1} / $count', style: const TextStyle(color: InkColors.dim, fontSize: 12)),
                  const Spacer(),
                  if (mode != ReadMode.strip) TextButton(onPressed: _cycleFit, child: Text(fitModeLabel(_fit))),
                  TextButton(
                    onPressed: () {
                      setState(() => _rtl = !_rtl);
                      _persistMode();
                    },
                    child: Text(_rtl ? '右起' : '左起'),
                  ),
                ],
              ),
              if (count > 1 && mode != ReadMode.strip)
                Slider(
                  value: (_page + 1).clamp(1, count).toDouble(),
                  min: 1,
                  max: count.toDouble(),
                  onChanged: (value) {
                    final page = value.round() - 1;
                    _setPage(page);
                    if (mode == ReadMode.spread) {
                      _pages?.jumpToPage(page ~/ 2);
                    } else {
                      _pages?.jumpToPage(page + 1);
                    }
                  },
                ),
            ],
          );
    return AnimatedSlide(
      offset: _chrome ? Offset.zero : Offset(0, top ? -1 : 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _chrome ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: ColoredBox(
            color: const Color(0xE6110F0D),
            child: SafeArea(
              bottom: !top,
              top: top,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: child),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chapters(ReaderDoc doc) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: InkColors.raised,
      builder: (context) => ListView.builder(
        itemCount: doc.chapters.length,
        itemBuilder: (context, index) {
          final selected = index == _chapter;
          return ListTile(
            title: Text(doc.chapters[index].name, style: TextStyle(color: selected ? InkColors.cinnabar : InkColors.paper)),
            subtitle: Text('${doc.chapters[index].pages.length} 页', style: const TextStyle(color: InkColors.mute)),
            onTap: () => Navigator.pop(context, index),
          );
        },
      ),
    );
    if (picked != null) _goChapter(picked);
  }
}

class ComicPage extends StatefulWidget {
  const ComicPage({required this.path, required this.fit, this.onAspect, this.onTap, super.key});
  final String path;
  final FitMode fit;
  final ValueChanged<double>? onAspect;
  final void Function(TapUpDetails details, Size size)? onTap;

  @override
  State<ComicPage> createState() => _ComicPageState();
}

class _ComicPageState extends State<ComicPage> {
  final _transform = TransformationController();
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect;
  Timer? _tapTimer;
  Offset? _focal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  void _listen() {
    _stream?.removeListener(_listener!);
    final provider = FileImage(File(widget.path));
    _listener = ImageStreamListener((info, _) {
      final aspect = info.image.height / info.image.width;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_aspect != null && (_aspect! - aspect).abs() <= 0.01) return;
        setState(() => _aspect = aspect);
        widget.onAspect?.call(aspect);
      });
    }, onError: (_, _) {});
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener!);
  }

  @override
  void didUpdateWidget(covariant ComicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _listen();
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    if (_listener != null) _stream?.removeListener(_listener!);
    _transform.dispose();
    super.dispose();
  }

  void _zoom() {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    final focal = _focal ?? Offset.zero;
    _transform.value = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(2, 2, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final image = Image.file(
          File(widget.path),
          fit: widget.fit == FitMode.width ? BoxFit.fitWidth : BoxFit.contain,
          width: widget.fit == FitMode.width ? constraints.maxWidth : null,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: (constraints.maxWidth * dpr).clamp(1, 2000).round(),
          errorBuilder: (_, _, _) => const Center(child: Text('这一页无法显示', style: TextStyle(color: InkColors.mute))),
        );
        final height = widget.fit == FitMode.width && _aspect != null
            ? math.max(constraints.maxHeight, constraints.maxWidth * _aspect!)
            : constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (details) => _focal = details.localPosition,
          onDoubleTap: () {
            _tapTimer?.cancel();
            _zoom();
          },
          onTapUp: (details) {
            _tapTimer?.cancel();
            _tapTimer = Timer(const Duration(milliseconds: 220), () {
              widget.onTap?.call(details, Size(constraints.maxWidth, constraints.maxHeight));
            });
          },
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 4,
            child: SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: widget.fit == FitMode.contain ? Center(child: image) : Align(alignment: Alignment.topCenter, child: image),
            ),
          ),
        );
      },
    );
  }
}
