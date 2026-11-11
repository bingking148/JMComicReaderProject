import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../engine/client.dart';
import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';
import '../ui/widgets.dart';
import 'policy.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.albumId, this.initialChapterId, super.key});
  final int albumId;
  final String? initialChapterId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const _engine = MethodChannel('jmcomic/engine');

  ReaderDoc? _doc;
  String? _error;
  int _chapter = 0;
  int _page = 0;
  double _offset = 0;
  ReadMode _choice = ReadMode.smart;
  FitMode _fit = FitMode.width;
  bool _rtl = false;
  bool _chrome = false;
  double? _aspect;
  Timer? _save;
  Timer? _persist;
  PageController? _pages;
  ScrollController? _scroll;
  BoxConstraints? _constraints;
  int _cacheSize = 0;
  int _cacheBytes = 0;
  double _dim = 0;
  String _background = 'ink';
  String _orientation = 'free';
  bool _awake = true;
  double _stripSpeed = 0;
  Timer? _glide;
  DateTime _glideAt = DateTime.fromMillisecondsSinceEpoch(0);

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
    _engine.setMethodCallHandler((call) async {
      if (!mounted || call.method != 'volume') return;
      _turn(call.arguments == 'prev' ? -1 : 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    try {
      final doc = await SessionScope.of(context).api.reader(widget.albumId);
      if (!mounted) return;
      var index = doc.chapters.indexWhere(
        (c) =>
            c.id ==
            (widget.initialChapterId?.isNotEmpty == true
                ? widget.initialChapterId
                : doc.chapterId),
      );
      if (index < 0) index = 0;
      final sameChapter =
          doc.chapters.isNotEmpty && doc.chapters[index].id == doc.chapterId;
      final settings = SessionScope.of(context).settings;
      setState(() {
        _doc = doc;
        _choice = readModeFromName(doc.mode);
        _fit = fitModeFromName(doc.fit);
        _rtl = doc.rtl;
        _background = settings.readerBackground;
        _orientation = settings.orientation;
        _awake = settings.screenStaysOn;
        _dim = settings.readerDim.clamp(0, 0.6);
        _stripSpeed = settings.stripSpeed;
        _chapter = index;
        _page = sameChapter ? math.max(0, doc.page - 1) : 0;
        _offset = sameChapter ? doc.offset : 0;
      });
      _bindControllers();
      _syncSystemUi();
      _precache();
      _applyRoom();
    } on EngineException catch (err) {
      if (!mounted) return;
      setState(() => _error = err.message);
    }
  }

  ReadMode _controllerMode() {
    if (_choice == ReadMode.strip ||
        _choice == ReadMode.spread ||
        _choice == ReadMode.single) {
      return _choice;
    }
    final box = _constraints;
    if (box == null || _aspect == null) return ReadMode.single;
    return resolveSmart(
      aspect: _aspect!,
      width: box.maxWidth,
      height: box.maxHeight,
    );
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
    _save?.cancel();
    _persist?.cancel();
    _glide?.cancel();
    _pages?.dispose();
    _scroll?.dispose();
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = _cacheSize;
    cache.maximumSizeBytes = _cacheBytes;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    unawaited(_wake(false));
    unawaited(_volumeKeys(false));
    _engine.setMethodCallHandler(null);
    super.dispose();
  }

  void _applyRoom() {
    final orientations = switch (_orientation) {
      'portrait' => const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
      'landscape' => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      _ => DeviceOrientation.values,
    };
    SystemChrome.setPreferredOrientations(orientations);
    unawaited(_wake(_awake));
    unawaited(_volumeKeys(true));
    _armGlide();
  }

  Future<void> _wake(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> _volumeKeys(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _engine.invokeMethod('volumeTurns', {'enabled': on});
    } catch (_) {}
  }

  void _armGlide() {
    _glide?.cancel();
    if (_stripSpeed <= 0) return;
    _glideAt = DateTime.now();
    _glide = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (!mounted || _chrome || _stripSpeed <= 0) return;
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      final now = DateTime.now();
      final dt = now.difference(_glideAt).inMilliseconds / 1000;
      _glideAt = now;
      final max = scroll.position.maxScrollExtent;
      final next = (scroll.offset + _stripSpeed * dt).clamp(0.0, max);
      if (next <= scroll.offset) return;
      scroll.jumpTo(next);
      _offset = next;
    });
  }

  ReadMode _effective(BoxConstraints constraints) {
    if (_choice != ReadMode.smart) return _choice;
    final aspect = _aspect;
    if (aspect == null) return ReadMode.single;
    return resolveSmart(
      aspect: aspect,
      width: constraints.maxWidth,
      height: constraints.maxHeight,
    );
  }

  void _syncSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      _chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    _syncSystemUi();
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
        await SessionScope.of(context).api
            .saveProgress(widget.albumId, chapter.id, _page + 1, offset);
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
  }

  void _goChapter(int index, {int page = 0, double offset = 0}) {
    final doc = _doc;
    if (doc == null || index < 0 || index >= doc.chapters.length) return;
    setState(() {
      _chapter = index;
      _page = page
          .clamp(0, math.max(0, doc.chapters[index].pages.length - 1))
          .toInt();
      _offset = offset;
      _aspect = null;
    });
    _bindControllers();
    _scheduleSave();
    _precache();
  }

  ReadMode _layoutMode() {
    final box = _constraints;
    if (box == null) {
      return _choice == ReadMode.strip ? ReadMode.strip : ReadMode.single;
    }
    return _effective(box);
  }

  void _jumpToPage(int page) {
    final chapter = _current;
    if (chapter == null || chapter.pages.isEmpty) return;
    final next = page.clamp(0, chapter.pages.length - 1);
    final layout = _layoutMode();
    _setPage(next);
    if (layout == ReadMode.strip) {
      final scroll = _scroll;
      final box = _constraints;
      if (scroll != null && scroll.hasClients && box != null) {
        final width = math.min(box.maxWidth, 920.0);
        final aspect = _aspect ?? 1.4;
        final target = next * width * aspect;
        scroll.jumpTo(target.clamp(0, scroll.position.maxScrollExtent));
        _offset = scroll.offset;
        _scheduleSave();
      }
      return;
    }
    if (layout == ReadMode.spread) {
      _pages?.jumpToPage(next ~/ 2);
      return;
    }
    _pages?.jumpToPage(next + 1);
  }

  void _scrubTo(ReadMode mode, int count, double t) {
    final fraction = t.clamp(0.0, 1.0);
    if (mode == ReadMode.strip) {
      final scroll = _scroll;
      if (scroll != null && scroll.hasClients) {
        final next = fraction * scroll.position.maxScrollExtent;
        scroll.jumpTo(next);
        _offset = next;
        _scheduleSave();
        setState(() {});
      }
      return;
    }
    if (count <= 1) return;
    _jumpToPage((fraction * (count - 1)).round());
  }

  void _turn(int delta) {
    final mode =
        _choice == ReadMode.strip ||
            (_choice == ReadMode.smart && _aspect != null && _aspect! >= 2.15)
        ? ReadMode.strip
        : (_choice == ReadMode.spread ? ReadMode.spread : ReadMode.single);
    if (mode == ReadMode.strip) {
      final scroll = _scroll;
      if (scroll == null || !scroll.hasClients) return;
      final target =
          scroll.offset + delta * scroll.position.viewportDimension * 0.86;
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
    _pages?.animateToPage(
      next + 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
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
    _pages?.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _persistMode() async {
    final session = SessionScope.of(context);
    await session.saveSettings(
      session.settings.copyWith(
        readerMode: readModeName(_choice),
        fitMode: fitModeName(_fit),
        rtl: _rtl,
        readerBackground: _background,
        keepAwake: _awake ? 'on' : 'off',
        orientation: _orientation,
        readerDim: _dim,
        stripSpeed: _stripSpeed,
      ),
    );
  }

  void _rememberPrefs() {
    _persist?.cancel();
    _persist = Timer(const Duration(milliseconds: 280), () {
      if (mounted) unawaited(_persistMode());
    });
  }

  void _cycleMode() {
    const order = [
      ReadMode.smart,
      ReadMode.single,
      ReadMode.spread,
      ReadMode.strip,
    ];
    setState(
      () => _choice = order[(order.indexOf(_choice) + 1) % order.length],
    );
    _bindControllers();
    _armGlide();
    _persistMode();
  }

  void _cycleFit() {
    const order = [FitMode.width, FitMode.contain, FitMode.height];
    setState(() => _fit = order[(order.indexOf(_fit) + 1) % order.length]);
    _persistMode();
  }

  Color _pageColor() {
    switch (_background) {
      case 'paper':
        return const Color(0xFFE4D7C3);
      case 'gray':
        return const Color(0xFF2A2A2A);
      default:
        return InkColors.read;
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: _pageColor(),
      body: doc == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 72, child: ProgressRule(value: 0)),
                  const SizedBox(height: 14),
                  Text(
                    _error ?? '正在打开',
                    style: const TextStyle(color: InkColors.mute, fontSize: 13),
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                _constraints = constraints;
                final mode = _effective(constraints);
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                        _turn(_rtl ? -1 : 1),
                    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                        _turn(_rtl ? 1 : -1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _turn(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _turn(-1),
                    const SingleActivator(LogicalKeyboardKey.space): () =>
                        _turn(1),
                    const SingleActivator(LogicalKeyboardKey.keyM): _cycleMode,
                    const SingleActivator(LogicalKeyboardKey.keyF): _cycleFit,
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _toggleChrome,
                    const SingleActivator(
                      LogicalKeyboardKey.audioVolumeDown,
                    ): () =>
                        _turn(1),
                    const SingleActivator(
                      LogicalKeyboardKey.audioVolumeUp,
                    ): () =>
                        _turn(-1),
                  },
                  child: Focus(
                    autofocus: true,
                    child: Column(
                      children: [
                        _chromeSlot(top: true, child: _topBar(doc)),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _viewport(mode, constraints),
                              ),
                              if (_dim > 0)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: ColoredBox(
                                      color: Color.fromRGBO(0, 0, 0, _dim),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _chromeSlot(top: false, child: _bottomBar(doc, mode)),
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
      return const Center(
        child: Text('这一章没有页面', style: TextStyle(color: InkColors.mute)),
      );
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
          onTap: (details, size) =>
              _handleTap(details.localPosition.dx, size.width),
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
            const SizedBox(width: 14),
            Expanded(child: _spreadSide(chapter, _rtl ? left : right)),
          ],
        );
      },
    );
  }

  Widget _spreadSide(ReaderChapter chapter, int index) {
    if (index < 0 || index >= chapter.pages.length) {
      return const ColoredBox(color: InkColors.read);
    }
    return ComicPage(
      path: chapter.pages[index],
      fit: FitMode.contain,
      onAspect: index == 0 ? _rememberAspect : null,
      onTap: (details, size) =>
          _handleTap(details.localPosition.dx, size.width),
    );
  }

  Widget _strip(ReaderChapter chapter, BoxConstraints constraints) {
    final scroll = _scroll;
    if (scroll == null) return const SizedBox.shrink();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification ||
            notification is ScrollUpdateNotification) {
          _offset = scroll.offset;
          if (notification is ScrollEndNotification) _scheduleSave();
          if (_chrome && mounted) setState(() {});
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
          return Center(
            child: GestureDetector(
              onTapUp: (details) {
                if ((details.localPosition.dx - width / 2).abs() <
                    width * 0.22) {
                  _toggleChrome();
                }
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
                  child: Center(
                    child: Text(
                      '这一页无法显示',
                      style: TextStyle(color: InkColors.mute),
                    ),
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
        : (previous
              ? '上一章  ${doc.chapters[_chapter - 1].name}'
              : '下一章  ${doc.chapters[_chapter + 1].name}');
    return Center(
      child: TextButton(
        onPressed: !has
            ? null
            : () => _goChapter(
                previous ? _chapter - 1 : _chapter + 1,
                page: previous ? 1 << 20 : 0,
              ),
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

  void _setMode(ReadMode mode) {
    if (_choice == mode) return;
    setState(() => _choice = mode);
    _bindControllers();
    _armGlide();
    unawaited(_persistMode());
  }

  void _setFit(FitMode fit) {
    if (_fit == fit) return;
    setState(() => _fit = fit);
    unawaited(_persistMode());
  }

  void _setDirection(bool rtl) {
    if (_rtl == rtl) return;
    setState(() => _rtl = rtl);
    unawaited(_persistMode());
  }

  void _setBackground(String id) {
    if (_background == id) return;
    setState(() => _background = id);
    unawaited(_persistMode());
  }

  void _setAwake(bool on) {
    if (_awake == on) return;
    setState(() => _awake = on);
    _applyRoom();
    unawaited(_persistMode());
  }

  void _setOrientation(String value) {
    if (_orientation == value) return;
    setState(() => _orientation = value);
    _applyRoom();
    unawaited(_persistMode());
  }

  Widget _chromeSlot({required bool top, required Widget child}) {
    return ClipRect(
      child: AnimatedAlign(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        heightFactor: _chrome ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _topBar(ReaderDoc doc) {
    final chapter = _current;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: InkColors.bg,
        border: Border(bottom: BorderSide(color: InkColors.line)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Row(
            children: [
              _quiet('返回', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      chapter?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: InkColors.mute,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              _quiet('目录', onTap: () => _chapters(doc)),
              _quiet('设置', onTap: _openSettings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(ReaderDoc doc, ReadMode mode) {
    final chapter = _current;
    final count = chapter?.pages.length ?? 0;
    final atStart = _chapter <= 0;
    final atEnd = _chapter >= doc.chapters.length - 1;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: InkColors.bg,
        border: Border(top: BorderSide(color: InkColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: Row(
            children: [
              _quiet(
                '上一话',
                onTap: atStart
                    ? null
                    : () => _goChapter(_chapter - 1, page: 1 << 20),
              ),
              Expanded(child: _pageSlider(mode, count)),
              _quiet(
                _pageWord(mode, count),
                onTap: count == 0 ? null : _openPages,
              ),
              _quiet(
                '下一话',
                onTap: atEnd ? null : () => _goChapter(_chapter + 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pageWord(ReadMode mode, int count) {
    if (mode == ReadMode.strip) {
      final scroll = _scroll;
      if (scroll == null ||
          !scroll.hasClients ||
          scroll.position.maxScrollExtent <= 0) {
        return '长条';
      }
      final pct = (100 * scroll.offset / scroll.position.maxScrollExtent)
          .round()
          .clamp(0, 100);
      return '$pct%';
    }
    if (count <= 0) return '0 / 0';
    return '${_page + 1} / $count';
  }

  double _fraction(ReadMode mode, int count) {
    if (mode == ReadMode.strip) {
      final scroll = _scroll;
      if (scroll != null &&
          scroll.hasClients &&
          scroll.position.maxScrollExtent > 0) {
        return (scroll.offset / scroll.position.maxScrollExtent).clamp(
          0.0,
          1.0,
        );
      }
      return 0;
    }
    if (count <= 1) return 0;
    return (_page / (count - 1)).clamp(0.0, 1.0);
  }

  Widget _pageSlider(ReadMode mode, int count) {
    return _ThinSlider(
      value: _fraction(mode, count),
      onChanged: (t) => _scrubTo(mode, count, t),
    );
  }

  Widget _quiet(String label, {required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1.1,
            color: onTap == null ? InkColors.mute : InkColors.paper,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  Future<void> _chapters(ReaderDoc doc) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: InkColors.raised,
      elevation: 0,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(560, MediaQuery.sizeOf(context).width),
      ),
      builder: (context) {
        final height = math.min(
          MediaQuery.sizeOf(context).height * 0.7,
          64 + doc.chapters.length * 48.0,
        );
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHead(title: '目录'),
              const Divider(height: 1, color: InkColors.line),
              Expanded(
                child: ListView.builder(
                  itemCount: doc.chapters.length,
                  itemBuilder: (context, index) {
                    final selected = index == _chapter;
                    final chapter = doc.chapters[index];
                    return InkWell(
                      onTap: () => Navigator.pop(context, index),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: selected
                                  ? InkColors.cinnabar
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chapter.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? InkColors.cinnabar
                                        : InkColors.paper,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${chapter.pages.length} 页',
                                style: const TextStyle(
                                  color: InkColors.mute,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    _goChapter(picked);
  }

  Future<void> _openPages() async {
    final chapter = _current;
    if (chapter == null || chapter.pages.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: InkColors.raised,
      elevation: 0,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(720, MediaQuery.sizeOf(context).width),
      ),
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.72;
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetHead(title: '页面', trailing: chapter.name),
              const Divider(height: 1, color: InkColors.line),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 148,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.66,
                  ),
                  itemCount: chapter.pages.length,
                  itemBuilder: (context, index) {
                    final selected = index == _page;
                    final dpr = MediaQuery.devicePixelRatioOf(context);
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, index),
                      child: Column(
                        children: [
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected
                                      ? InkColors.cinnabar
                                      : InkColors.line,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Image.file(
                                File(chapter.pages[index]),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                filterQuality: FilterQuality.low,
                                cacheWidth: (120 * dpr).round(),
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: InkColors.bg),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1,
                              color: selected
                                  ? InkColors.cinnabar
                                  : InkColors.mute,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    _jumpToPage(picked);
  }

  Future<void> _openSettings() async {
    var mode = _choice;
    var fit = _fit;
    var rtl = _rtl;
    var background = _background;
    var dim = _dim;
    var awake = _awake;
    var orientation = _orientation;
    var speed = _stripSpeed;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: InkColors.raised,
      elevation: 0,
      isScrollControlled: true,
      barrierColor: const Color(0x45000000),
      constraints: BoxConstraints(
        maxWidth: math.min(560, MediaQuery.sizeOf(context).width),
      ),
      builder: (context) {
        final height = math.min(
          540.0,
          MediaQuery.sizeOf(context).height * 0.78,
        );
        return StatefulBuilder(
          builder: (context, setSheet) {
            void refresh() => setSheet(() {});
            return SizedBox(
              height: height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SheetHead(title: '设置'),
                  const Divider(height: 1, color: InkColors.line),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                      children: [
                        _group(
                          '阅读',
                          _choices([
                            _pick('自适应', mode == ReadMode.smart, () {
                              mode = ReadMode.smart;
                              _setMode(mode);
                              refresh();
                            }),
                            _pick('单页', mode == ReadMode.single, () {
                              mode = ReadMode.single;
                              _setMode(mode);
                              refresh();
                            }),
                            _pick('跨页', mode == ReadMode.spread, () {
                              mode = ReadMode.spread;
                              _setMode(mode);
                              refresh();
                            }),
                            _pick('长条', mode == ReadMode.strip, () {
                              mode = ReadMode.strip;
                              _setMode(mode);
                              refresh();
                            }),
                          ]),
                        ),
                        _group(
                          '画面',
                          _choices([
                            _pick('适宽', fit == FitMode.width, () {
                              fit = FitMode.width;
                              _setFit(fit);
                              refresh();
                            }),
                            _pick('整页', fit == FitMode.contain, () {
                              fit = FitMode.contain;
                              _setFit(fit);
                              refresh();
                            }),
                            _pick('适高', fit == FitMode.height, () {
                              fit = FitMode.height;
                              _setFit(fit);
                              refresh();
                            }),
                            _pick('左起', !rtl, () {
                              rtl = false;
                              _setDirection(false);
                              refresh();
                            }),
                            _pick('右起', rtl, () {
                              rtl = true;
                              _setDirection(true);
                              refresh();
                            }),
                          ]),
                        ),
                        _group(
                          '底色',
                          Row(
                            children: [
                              _swatch('ink', InkColors.read, '墨色', background, (
                                id,
                              ) {
                                background = id;
                                _setBackground(id);
                                refresh();
                              }),
                              _swatch(
                                'gray',
                                const Color(0xFF2A2A2A),
                                '灰色',
                                background,
                                (id) {
                                  background = id;
                                  _setBackground(id);
                                  refresh();
                                },
                              ),
                              _swatch(
                                'paper',
                                const Color(0xFFE4D7C3),
                                '纸色',
                                background,
                                (id) {
                                  background = id;
                                  _setBackground(id);
                                  refresh();
                                },
                              ),
                            ],
                          ),
                        ),
                        _group(
                          '遮光',
                          _ThinSlider(
                            value: (dim / 0.6).clamp(0.0, 1.0),
                            onChanged: (t) {
                              dim = t * 0.6;
                              setState(() => _dim = dim);
                              _rememberPrefs();
                              refresh();
                            },
                          ),
                        ),
                        _group(
                          '屏幕',
                          _choices([
                            _pick('常亮', awake, () {
                              awake = true;
                              _setAwake(true);
                              refresh();
                            }),
                            _pick('会息屏', !awake, () {
                              awake = false;
                              _setAwake(false);
                              refresh();
                            }),
                            _pick('随方向', orientation == 'free', () {
                              orientation = 'free';
                              _setOrientation('free');
                              refresh();
                            }),
                            _pick('竖屏', orientation == 'portrait', () {
                              orientation = 'portrait';
                              _setOrientation('portrait');
                              refresh();
                            }),
                            _pick('横屏', orientation == 'landscape', () {
                              orientation = 'landscape';
                              _setOrientation('landscape');
                              refresh();
                            }),
                          ]),
                        ),
                        _group(
                          '长条滚动',
                          _ThinSlider(
                            value: (speed / 160).clamp(0.0, 1.0),
                            onChanged: (t) {
                              speed = t * 160;
                              _stripSpeed = speed;
                              _armGlide();
                              setState(() {});
                              _rememberPrefs();
                              refresh();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _group(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              title,
              style: const TextStyle(
                color: InkColors.mute,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }

  Widget _choices(List<Widget> children) {
    return Wrap(
      spacing: 2,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _pick(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1.1,
            color: on ? InkColors.cinnabar : InkColors.paper,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _swatch(
    String id,
    Color color,
    String label,
    String current,
    ValueChanged<String> onPick,
  ) {
    final on = current == id;
    return GestureDetector(
      onTap: () => onPick(id),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 14, 4),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                border: Border.all(
                  color: on ? InkColors.cinnabar : InkColors.line,
                  width: on ? 1.5 : 1,
                ),
              ),
              child: const SizedBox(width: 28, height: 28),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: on ? InkColors.cinnabar : InkColors.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHead extends StatelessWidget {
  const _SheetHead({required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (trailing != null)
            Flexible(
              child: Text(
                trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: InkColors.mute, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThinSlider extends StatelessWidget {
  const _ThinSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const inset = 12.0;
        final width = constraints.maxWidth;
        final track = math.max(0.0, width - inset * 2);
        final fraction = value.clamp(0.0, 1.0);
        void apply(double dx) {
          if (track <= 0) return;
          onChanged(((dx - inset) / track).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => apply(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => apply(details.localPosition.dx),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: inset),
                  child: SizedBox(
                    height: 2,
                    child: Stack(
                      children: [
                        const ColoredBox(
                          color: InkColors.line,
                          child: SizedBox.expand(),
                        ),
                        if (fraction > 0)
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: const ColoredBox(
                              color: InkColors.cinnabar,
                              child: SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: inset + track * fraction - 5,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: InkColors.cinnabar,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox(width: 10, height: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ComicPage extends StatefulWidget {
  const ComicPage({
    required this.path,
    required this.fit,
    this.onAspect,
    this.onTap,
    super.key,
  });
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
          fit: switch (widget.fit) {
            FitMode.height => BoxFit.fitHeight,
            FitMode.contain => BoxFit.contain,
            FitMode.width => BoxFit.fitWidth,
          },
          width: widget.fit == FitMode.width ? constraints.maxWidth : null,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: (constraints.maxWidth * dpr).clamp(1, 2000).round(),
          errorBuilder: (_, _, _) => const Center(
            child: Text('这一页无法显示', style: TextStyle(color: InkColors.mute)),
          ),
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
              widget.onTap?.call(
                details,
                Size(constraints.maxWidth, constraints.maxHeight),
              );
            });
          },
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 4,
            child: SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: widget.fit == FitMode.width
                  ? Align(alignment: Alignment.topCenter, child: image)
                  : Center(child: image),
            ),
          ),
        );
      },
    );
  }
}
