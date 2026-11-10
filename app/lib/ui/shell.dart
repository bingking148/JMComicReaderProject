import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';
import 'discover.dart';
import 'downloads.dart';
import 'library.dart';
import 'settings.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _items = [
    (label: '发现', icon: _Mark.search),
    (label: '书架', icon: _Mark.shelf),
    (label: '下载', icon: _Mark.down),
    (label: '设置', icon: _Mark.gear),
  ];

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final activeJobs = session.jobs.where((job) => job.active).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        const pages = [DiscoverPage(), LibraryPage(), DownloadsPage(), SettingsPage()];
        final body = IndexedStack(index: _index, children: pages);
        if (!wide) {
          return Scaffold(
            body: body,
            bottomNavigationBar: ColoredBox(
              color: InkColors.raised,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 62,
                  child: Row(
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Expanded(
                          child: _RailButton(
                            label: _items[i].label,
                            kind: _items[i].icon,
                            active: _index == i,
                            badge: i == 2 ? activeJobs : 0,
                            compact: true,
                            onTap: () => setState(() => _index = i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              _Rail(
                index: _index,
                badge: activeJobs,
                onSelect: (value) => setState(() => _index = value),
              ),
              const VerticalDivider(width: 1, color: InkColors.line),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.index, required this.badge, required this.onSelect});
  final int index;
  final int badge;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: ColoredBox(
        color: InkColors.raised,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 22),
              for (var i = 0; i < _ShellState._items.length; i++)
                _RailButton(
                  label: _ShellState._items[i].label,
                  kind: _ShellState._items[i].icon,
                  active: index == i,
                  badge: i == 2 ? badge : 0,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.kind,
    required this.active,
    required this.badge,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final _Mark kind;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 14),
        decoration: BoxDecoration(
          border: Border(
            left: compact ? BorderSide.none : BorderSide(color: active ? InkColors.cinnabar : Colors.transparent, width: 2),
            top: compact ? BorderSide(color: active ? InkColors.cinnabar : Colors.transparent, width: 2) : BorderSide.none,
          ),
        ),
        child: Column(
          children: [
            _NavIcon(kind: kind, active: active, badge: badge),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, color: active ? InkColors.paper : InkColors.mute, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

enum _Mark { search, shelf, down, gear }

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.kind, required this.active, required this.badge});
  final _Mark kind;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final icon = CustomPaint(
      size: const Size(22, 22),
      painter: _MarkPainter(kind, active ? InkColors.paper : InkColors.mute),
    );
    if (badge <= 0) return icon;
    return Badge(
      label: Text('$badge'),
      backgroundColor: InkColors.cinnabar,
      child: icon,
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.kind, this.color);
  final _Mark kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.square;
    switch (kind) {
      case _Mark.search:
        canvas.drawCircle(const Offset(9, 9), 5.5, paint);
        canvas.drawLine(const Offset(13.2, 13.2), const Offset(18, 18), paint);
      case _Mark.shelf:
        canvas.drawLine(const Offset(3, 7), const Offset(19, 7), paint);
        canvas.drawLine(const Offset(3, 15), const Offset(19, 15), paint);
        canvas.drawRect(const Rect.fromLTWH(6, 4, 3, 6), paint);
        canvas.drawRect(const Rect.fromLTWH(12, 9, 4, 6), paint);
      case _Mark.down:
        canvas.drawLine(const Offset(11, 3), const Offset(11, 14), paint);
        canvas.drawLine(const Offset(7, 10), const Offset(11, 15), paint);
        canvas.drawLine(const Offset(15, 10), const Offset(11, 15), paint);
        canvas.drawLine(const Offset(4, 18), const Offset(18, 18), paint);
      case _Mark.gear:
        canvas.drawCircle(const Offset(11, 11), 3.2, paint);
        canvas.drawCircle(const Offset(11, 11), 7.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => oldDelegate.color != color || oldDelegate.kind != kind;
}
