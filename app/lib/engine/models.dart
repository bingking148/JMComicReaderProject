class Summary {
  const Summary({
    required this.id,
    required this.title,
    required this.author,
    this.description = '',
    this.tags = const [],
    this.favorites = 0,
    this.pageCount = 0,
    this.downloaded = false,
    this.partial = false,
  });

  final int id;
  final String title;
  final String author;
  final String description;
  final List<String> tags;
  final int favorites;
  final int pageCount;
  final bool downloaded;
  final bool partial;

  Summary copyWith({int? favorites, List<String>? tags, String? author, String? description, int? pageCount, bool? downloaded}) {
    return Summary(
      id: id,
      title: title,
      author: author ?? this.author,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      favorites: favorites ?? this.favorites,
      pageCount: pageCount ?? this.pageCount,
      downloaded: downloaded ?? this.downloaded,
      partial: partial,
    );
  }

  factory Summary.fromJson(Map<String, dynamic> json) {
    return Summary(
      id: asInt(json['id']),
      title: (json['title'] ?? '') as String,
      author: (json['author'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      tags: stringList(json['tags']),
      favorites: asInt(json['favorites']),
      pageCount: asInt(json['pageCount']),
      downloaded: json['downloaded'] == true,
      partial: json['partial'] == true,
    );
  }
}

class ChapterRef {
  const ChapterRef({required this.id, required this.name, required this.sort, this.pages = 0});
  final int id;
  final String name;
  final int sort;
  final int pages;

  factory ChapterRef.fromJson(Map<String, dynamic> json) => ChapterRef(
        id: asInt(json['id']),
        name: (json['name'] ?? '') as String,
        sort: asInt(json['sort']),
        pages: asInt(json['pages']),
      );
}

class Album {
  const Album({
    required this.summary,
    this.works = const [],
    this.actors = const [],
    this.chapters = const [],
    this.related = const [],
  });

  final Summary summary;
  final List<String> works;
  final List<String> actors;
  final List<ChapterRef> chapters;
  final List<Summary> related;

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      summary: Summary.fromJson(json),
      works: stringList(json['works']),
      actors: stringList(json['actors']),
      chapters: (json['chapters'] as List<dynamic>? ?? const [])
          .map((e) => ChapterRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      related: (json['related'] as List<dynamic>? ?? const [])
          .map((e) => Summary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.query,
    required this.page,
    required this.total,
    required this.direct,
    required this.items,
  });

  final String query;
  final int page;
  final int total;
  final bool direct;
  final List<Summary> items;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      query: (json['query'] ?? '') as String,
      page: asInt(json['page']),
      total: asInt(json['total']),
      direct: json['direct'] == true,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((e) => Summary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Job {
  const Job({
    required this.albumId,
    required this.title,
    required this.status,
    required this.done,
    required this.total,
    required this.message,
    this.error = '',
  });

  final int albumId;
  final String title;
  final String status;
  final int done;
  final int total;
  final String message;
  final String error;

  bool get active => status == 'running' || status == 'queued';
  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1);

  /// Progress bar for a download row. Only an in-flight job with no measured
  /// progress keeps moving; canceled, paused, and failed rows stay still.
  double? get track {
    if (active && fraction <= 0) return null;
    return fraction;
  }

  factory Job.fromJson(Map<String, dynamic> json) => Job(
        albumId: asInt(json['albumId']),
        title: (json['title'] ?? '') as String,
        status: (json['status'] ?? '') as String,
        done: asInt(json['done']),
        total: asInt(json['total']),
        message: (json['message'] ?? '') as String,
        error: (json['error'] ?? '') as String,
      );
}

class Comic {
  const Comic({
    required this.id,
    required this.title,
    required this.author,
    this.tags = const [],
    this.pages = 0,
    this.coverPath = '',
    this.dir = '',
    this.downloadTime = '',
    this.lastRead = '',
    this.fileSize = 0,
    this.status = '',
    this.chapterId = '',
    this.page = 1,
  });

  final int id;
  final String title;
  final String author;
  final List<String> tags;
  final int pages;
  final String coverPath;
  final String dir;
  final String downloadTime;
  final String lastRead;
  final int fileSize;
  final String status;
  final String chapterId;
  final int page;

  factory Comic.fromJson(Map<String, dynamic> json) => Comic(
        id: asInt(json['id']),
        title: (json['title'] ?? '') as String,
        author: (json['author'] ?? '') as String,
        tags: stringList(json['tags']),
        pages: asInt(json['pages']),
        coverPath: (json['coverPath'] ?? '') as String,
        dir: (json['dir'] ?? '') as String,
        downloadTime: (json['downloadTime'] ?? '') as String,
        lastRead: (json['lastRead'] ?? '') as String,
        fileSize: asInt(json['fileSize']),
        status: (json['status'] ?? '') as String,
        chapterId: (json['chapterId'] ?? '') as String,
        page: asInt(json['page']) == 0 ? 1 : asInt(json['page']),
      );
}

class ReaderChapter {
  const ReaderChapter({required this.id, required this.name, required this.pages});
  final String id;
  final String name;
  final List<String> pages;

  factory ReaderChapter.fromJson(Map<String, dynamic> json) => ReaderChapter(
        id: '${json['id'] ?? ''}',
        name: (json['name'] ?? '') as String,
        pages: (json['pages'] as List<dynamic>? ?? const []).map((e) => e as String).toList(),
      );
}

class ReaderDoc {
  const ReaderDoc({
    required this.id,
    required this.title,
    required this.chapters,
    required this.chapterId,
    required this.page,
    required this.offset,
    required this.mode,
    required this.fit,
    required this.rtl,
  });

  final int id;
  final String title;
  final List<ReaderChapter> chapters;
  final String chapterId;
  final int page;
  final double offset;
  final String mode;
  final String fit;
  final bool rtl;

  factory ReaderDoc.fromJson(Map<String, dynamic> json) {
    final progress = (json['progress'] as Map<String, dynamic>?) ?? const {};
    return ReaderDoc(
      id: asInt(json['id']),
      title: (json['title'] ?? '') as String,
      chapters: (json['chapters'] as List<dynamic>? ?? const [])
          .map((e) => ReaderChapter.fromJson(e as Map<String, dynamic>))
          .toList(),
      chapterId: '${progress['chapterId'] ?? ''}',
      page: asInt(progress['page']) == 0 ? 1 : asInt(progress['page']),
      offset: (progress['offset'] as num?)?.toDouble() ?? 0,
      mode: (json['mode'] ?? 'smart') as String,
      fit: (json['fit'] ?? 'width') as String,
      rtl: json['rtl'] == true,
    );
  }
}

class Settings {
  const Settings({
    this.apiDomains = const [],
    this.imageDomains = const [],
    this.concurrency = 5,
    this.retry = 5,
    this.appVersion = '',
    this.autoUpdateDomains = true,
    this.ageAccepted = false,
    this.readerMode = 'smart',
    this.fitMode = 'width',
    this.rtl = false,
    this.dataDir = '',
  });

  final List<String> apiDomains;
  final List<String> imageDomains;
  final int concurrency;
  final int retry;
  final String appVersion;
  final bool autoUpdateDomains;
  final bool ageAccepted;
  final String readerMode;
  final String fitMode;
  final bool rtl;
  final String dataDir;

  Settings copyWith({
    List<String>? apiDomains,
    List<String>? imageDomains,
    int? concurrency,
    int? retry,
    bool? autoUpdateDomains,
    bool? ageAccepted,
    String? readerMode,
    String? fitMode,
    bool? rtl,
  }) {
    return Settings(
      apiDomains: apiDomains ?? this.apiDomains,
      imageDomains: imageDomains ?? this.imageDomains,
      concurrency: concurrency ?? this.concurrency,
      retry: retry ?? this.retry,
      appVersion: appVersion,
      autoUpdateDomains: autoUpdateDomains ?? this.autoUpdateDomains,
      ageAccepted: ageAccepted ?? this.ageAccepted,
      readerMode: readerMode ?? this.readerMode,
      fitMode: fitMode ?? this.fitMode,
      rtl: rtl ?? this.rtl,
      dataDir: dataDir,
    );
  }

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        apiDomains: stringList(json['apiDomains']),
        imageDomains: stringList(json['imageDomains']),
        concurrency: asInt(json['concurrency']) == 0 ? 5 : asInt(json['concurrency']),
        retry: asInt(json['retry']) == 0 ? 5 : asInt(json['retry']),
        appVersion: (json['appVersion'] ?? '') as String,
        autoUpdateDomains: json['autoUpdateDomains'] != false,
        ageAccepted: json['ageAccepted'] == true,
        readerMode: (json['readerMode'] ?? 'smart') as String,
        fitMode: (json['fitMode'] ?? 'width') as String,
        rtl: json['rtl'] == true,
        dataDir: (json['dataDir'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'apiDomains': apiDomains,
        'imageDomains': imageDomains,
        'concurrency': concurrency,
        'retry': retry,
        'appVersion': appVersion,
        'autoUpdateDomains': autoUpdateDomains,
        'ageAccepted': ageAccepted,
        'readerMode': readerMode,
        'fitMode': fitMode,
        'rtl': rtl,
        'dataDir': dataDir,
      };
}

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

List<String> stringList(Object? value) {
  if (value is List) {
    return value.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

int? parseJmId(String query) {
  final match = RegExp(r'^(?:JM|jm)?(\d+)$').firstMatch(query.trim());
  if (match == null) return null;
  final id = int.tryParse(match.group(1)!);
  if (id == null || id <= 0) return null;
  return id;
}

String compactCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) {
    final digits = n >= 100000 ? 0 : 1;
    return '${(n / 10000).toStringAsFixed(digits)}万';
  }
  return '$n';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
