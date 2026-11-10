import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../session.dart';
import '../theme.dart';

class Wordmark extends StatelessWidget {
  const Wordmark({this.compact = false, super.key});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 18 : 22,
          height: compact ? 18 : 22,
          alignment: Alignment.center,
          color: InkColors.cinnabar,
          child: Text(
            '墨',
            style: TextStyle(color: const Color(0xFFFFF6EC), fontSize: compact ? 11 : 13, height: 1),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '墨册',
          style: TextStyle(
            fontSize: compact ? 18 : 28,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: InkColors.mute, fontSize: 12, letterSpacing: 1.6),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: InkColors.line))),
      );
}

class CoverImage extends StatelessWidget {
  const CoverImage({required this.id, this.path, super.key});
  final int id;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final local = path;
    if (local != null && local.isNotEmpty) {
      final file = File(local);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _fallback(id));
      }
    }
    final session = SessionScope.of(context);
    return Image.network(
      session.api.coverUrl(id),
      headers: {'X-Engine-Token': session.api.token},
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _fallback(id),
    );
  }
}

Widget _fallback(int id) {
  return ColoredBox(
    color: InkColors.raised,
    child: Center(
      child: Text('JM$id', style: const TextStyle(color: InkColors.mute, fontSize: 12)),
    ),
  );
}

class ComicTile extends StatefulWidget {
  const ComicTile({required this.summary, required this.onTap, this.coverPath, super.key});
  final Summary summary;
  final String? coverPath;
  final VoidCallback onTap;

  @override
  State<ComicTile> createState() => _ComicTileState();
}

class _ComicTileState extends State<ComicTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.summary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: _hover ? InkColors.cinnabar : InkColors.line),
                ),
                child: ClipRect(child: CoverImage(id: item.id, path: widget.coverPath)),
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.25)),
            const SizedBox(height: 3),
            Text(
              item.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: InkColors.mute, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: InkColors.brass.withValues(alpha: 0.7))),
      child: Text(text, style: const TextStyle(color: InkColors.brass, fontSize: 12)),
    );
  }
}

class QuietMessage extends StatelessWidget {
  const QuietMessage({required this.title, this.detail, super.key});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Hairline(),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail!, textAlign: TextAlign.center, style: const TextStyle(color: InkColors.mute, height: 1.45)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ProgressRule extends StatelessWidget {
  const ProgressRule({required this.value, super.key});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        height: 2,
        child: LinearProgressIndicator(
          value: value <= 0 ? null : value,
          color: InkColors.cinnabar,
          backgroundColor: InkColors.line,
        ),
      ),
    );
  }
}
