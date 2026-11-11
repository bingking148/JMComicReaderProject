import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class EngineClient {
  EngineClient({required this.base, required this.token, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String base;
  final String token;
  final http.Client _http;

  Map<String, String> get headers => {
        'X-Engine-Token': token,
        'Content-Type': 'application/json',
      };

  String coverUrl(int id) => '$base/v1/covers/$id';

  Future<Settings> settings() async => Settings.fromJson(await _send('GET', '/v1/settings'));

  Future<Settings> updateSettings(Settings settings) async {
    return Settings.fromJson(await _send('PUT', '/v1/settings', settings.toJson()));
  }

  Future<Settings> refreshDomains() async {
    return Settings.fromJson(await _send('POST', '/v1/settings/domains/refresh', const {}));
  }

  Future<SearchResult> search(String query, {int page = 1, String sort = 'latest'}) async {
    return SearchResult.fromJson(await _send('POST', '/v1/search', {
      'query': query,
      'page': page,
      'sort': sort,
    }));
  }

  Future<Map<int, Summary>> enrich(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final body = await _send('POST', '/v1/search/enrich', {'ids': ids});
    final raw = (body['items'] as Map<String, dynamic>? ?? const {});
    return raw.map((key, value) => MapEntry(int.parse(key), Summary.fromJson(value as Map<String, dynamic>)));
  }

  Future<List<String>> recentSearches() async {
    final body = await _send('GET', '/v1/history/search');
    return stringList(body['items']);
  }

  Future<Album> album(int id) async => Album.fromJson(await _send('GET', '/v1/albums/$id'));

  Future<Job> startDownload(int id, {bool restart = false}) async {
    return Job.fromJson(await _send('POST', '/v1/downloads', {'albumId': id, 'restart': restart}));
  }

  Future<List<Job>> downloads() async {
    final body = await _send('GET', '/v1/downloads');
    return (body['items'] as List<dynamic>? ?? const []).map((e) => Job.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> pause(int id) => _send('POST', '/v1/downloads/$id/pause', const {});
  Future<void> resume(int id) => _send('POST', '/v1/downloads/$id/resume', const {});
  Future<void> cancel(int id) => _send('DELETE', '/v1/downloads/$id');

  Future<List<Comic>> library() async {
    final body = await _send('GET', '/v1/library');
    return (body['items'] as List<dynamic>? ?? const []).map((e) => Comic.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteComic(int id) => _send('DELETE', '/v1/library/$id');

  Future<ReaderDoc> reader(int id) async => ReaderDoc.fromJson(await _send('GET', '/v1/library/$id/reader'));

  Future<void> saveProgress(int id, String chapterId, int page, double offset) {
    return _send('PUT', '/v1/library/$id/progress', {
      'chapterId': chapterId,
      'page': page,
      'offset': offset,
    });
  }

  Future<int> rescan() async {
    final body = await _send('POST', '/v1/library/rescan', const {});
    return asInt(body['imported']);
  }

  Future<ImportReport> importPath(String path) async {
    return ImportReport.fromJson(await _send('POST', '/v1/library/import', {'path': path}));
  }

  Future<StorageUse> storage() async => StorageUse.fromJson(await _send('GET', '/v1/storage'));

  Future<int> cacheBytes() async {
    final body = await _send('GET', '/v1/cache');
    return asInt(body['bytes']);
  }

  Future<void> clearCache() => _send('POST', '/v1/cache/clear', const {});

  Future<DataRootChange> relocateData(String path, {required bool move}) async {
    final uri = Uri.parse('$base/v1/data-root');
    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode({'path': path, 'mode': move ? 'move' : 'switch'}),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw EngineException('引擎返回了无法识别的数据');
    }
    final change = DataRootChange.fromJson(decoded);
    if (response.statusCode >= 400 && !change.restart) {
      throw EngineException((decoded['error'] as String?) ?? '没能更改数据目录');
    }
    return change;
  }

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$base$path');
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _http.get(uri, headers: headers);
        case 'POST':
          response = await _http.post(uri, headers: headers, body: jsonEncode(body ?? const {}));
        case 'PUT':
          response = await _http.put(uri, headers: headers, body: jsonEncode(body ?? const {}));
        case 'DELETE':
          response = await _http.delete(uri, headers: headers);
        default:
          throw EngineException('不支持的方法');
      }
    } catch (err) {
      if (err is EngineException) rethrow;
      throw EngineException('无法连接本地引擎');
    }
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw EngineException('引擎返回了无法识别的数据');
    }
    if (response.statusCode >= 400) {
      throw EngineException((decoded['error'] as String?) ?? '请求失败');
    }
    return decoded;
  }
}
