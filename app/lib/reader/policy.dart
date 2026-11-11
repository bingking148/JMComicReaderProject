import 'dart:math' as math;

enum ReadMode { smart, single, spread, strip }

enum FitMode { width, contain, height }

ReadMode readModeFromName(String name) {
  switch (name) {
    case 'single':
      return ReadMode.single;
    case 'spread':
      return ReadMode.spread;
    case 'strip':
      return ReadMode.strip;
    default:
      return ReadMode.smart;
  }
}

String readModeName(ReadMode mode) {
  switch (mode) {
    case ReadMode.smart:
      return 'smart';
    case ReadMode.single:
      return 'single';
    case ReadMode.spread:
      return 'spread';
    case ReadMode.strip:
      return 'strip';
  }
}

String readModeLabel(ReadMode mode) {
  switch (mode) {
    case ReadMode.smart:
      return '自适应';
    case ReadMode.single:
      return '单页';
    case ReadMode.spread:
      return '跨页';
    case ReadMode.strip:
      return '长条';
  }
}

FitMode fitModeFromName(String name) {
  switch (name) {
    case 'contain':
      return FitMode.contain;
    case 'height':
      return FitMode.height;
    default:
      return FitMode.width;
  }
}

String fitModeName(FitMode mode) {
  switch (mode) {
    case FitMode.contain:
      return 'contain';
    case FitMode.height:
      return 'height';
    case FitMode.width:
      return 'width';
  }
}

String fitModeLabel(FitMode mode) {
  switch (mode) {
    case FitMode.contain:
      return '整页';
    case FitMode.height:
      return '适高';
    case FitMode.width:
      return '适宽';
  }
}

/// Smart layout: very tall pages scroll as a strip; a wide, short viewport
/// shows a spread; everything else stays a single readable page.
ReadMode resolveSmart({
  required double aspect,
  required double width,
  required double height,
}) {
  if (aspect >= 2.15) return ReadMode.strip;
  final shortest = math.min(width, height);
  final landscape = width > height * 1.12;
  if (landscape && shortest >= 640 && aspect < 1.65 && aspect > 0) {
    return ReadMode.spread;
  }
  return ReadMode.single;
}
