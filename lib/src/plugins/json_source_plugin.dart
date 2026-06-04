import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../storage/app_storage.dart';
import 'magnet_item.dart';

class JsonSourcePlugin {
  const JsonSourcePlugin({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.enabled,
    required this.baseUrl,
    required this.capabilities,
    required this.headers,
    required this.search,
    required this.detail,
    required this.fields,
    required this.fileFields,
    required this.defaults,
  });

  final int schemaVersion;
  final String id;
  final String name;
  final bool enabled;
  final Uri baseUrl;
  final PluginCapabilities capabilities;
  final Map<String, String> headers;
  final PluginEndpoint search;
  final PluginEndpoint? detail;
  final Map<String, String> fields;
  final Map<String, String> fileFields;
  final Map<String, String> defaults;

  factory JsonSourcePlugin.fromJson(Map<String, Object?> json) {
    final Object? searchJson = json['search'];
    if (searchJson is! Map<String, Object?>) {
      throw const PluginException('插件缺少 search 配置');
    }

    final Object? detailJson = json['detail'];
    return JsonSourcePlugin(
      schemaVersion: _intValue(json['schemaVersion'], 1),
      id: _stringValue(json['id']),
      name: _stringValue(json['name']),
      enabled: _boolValue(json['enabled'], true),
      baseUrl: Uri.parse(_stringValue(json['baseUrl'])),
      capabilities: PluginCapabilities.fromJson(json['capabilities']),
      headers: _stringMap(json['headers']),
      search: PluginEndpoint.fromJson(searchJson),
      detail: detailJson is Map<String, Object?>
          ? PluginEndpoint.fromJson(detailJson)
          : null,
      fields: _stringMap(json['fields']),
      fileFields: _stringMap(json['fileFields']),
      defaults: _stringMap(json['defaults']),
    );
  }

  Future<PluginSearchResult> runSearch({
    required String query,
    required int page,
    http.Client? client,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final http.Response response = await _get(
      httpClient,
      search,
      _variablesForSearch(query: query, page: page),
      extraHeaders,
    );
    _throwIfHumanVerification(response);
    if (response.statusCode != 200) {
      throw PluginException('$name 搜索失败：HTTP ${response.statusCode}');
    }

    if (search.isHtml) {
      return parseSearchHtml(response.body, page: page);
    }

    final Object? decoded = jsonDecode(response.body);
    final Object? itemsValue = _valueAt(decoded, search.itemsPath);
    if (itemsValue is! List<Object?>) {
      throw PluginException('$name 搜索返回缺少列表：${search.itemsPath}');
    }

    final int total = _intValue(_valueAt(decoded, search.totalPath));
    final int currentPage = _intValue(
      _valueAt(decoded, search.currentPagePath),
      page,
    );
    final int lastPage = search.lastPagePath.isNotEmpty
        ? _intValue(_valueAt(decoded, search.lastPagePath), page)
        : _lastPageFromTotal(total, search.pageSize);

    return PluginSearchResult(
      items: itemsValue
          .whereType<Map<String, Object?>>()
          .map((Map<String, Object?> item) => _itemFromJson(item))
          .toList(growable: false),
      currentPage: currentPage <= 0 ? page : currentPage,
      lastPage: lastPage <= 0 ? page : lastPage,
      total: total,
    );
  }

  PluginSearchResult parseSearchHtml(String html, {required int page}) {
    final List<Map<String, Object?>> items = _htmlItems(html, search);
    final int total = _firstIntMatch(html, search.totalPattern, items.length);
    final int lastPage = search.lastPagePattern.isNotEmpty
        ? _firstIntMatch(html, search.lastPagePattern, page)
        : _lastPageFromTotal(total, search.pageSize);
    return PluginSearchResult(
      items: items
          .map((Map<String, Object?> item) => _itemFromJson(item))
          .where((MagnetItem item) => item.sourceItemId.isNotEmpty)
          .toList(growable: false),
      currentPage: page,
      lastPage: lastPage <= 0 ? page : lastPage,
      total: total,
    );
  }

  Uri resolveSearchUrl({required String query, required int page}) {
    return _resolveEndpoint(
      search.url,
      _variablesForSearch(query: query, page: page),
    );
  }

  Future<MagnetItem> runDetail(
    MagnetItem item, {
    http.Client? client,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final PluginEndpoint? endpoint = detail;
    if (endpoint == null) {
      return item;
    }

    final http.Client httpClient = client ?? http.Client();
    final http.Response response = await _get(
      httpClient,
      endpoint,
      _variablesForItem(item),
      extraHeaders,
    );
    _throwIfHumanVerification(response);
    if (response.statusCode != 200) {
      throw PluginException('$name 详情失败：HTTP ${response.statusCode}');
    }

    if (endpoint.isHtml) {
      return parseDetailHtml(item, response.body);
    }

    final Object? decoded = jsonDecode(response.body);
    final Object? root = endpoint.rootPath.isEmpty
        ? decoded
        : _valueAt(decoded, endpoint.rootPath);
    if (root is! Map<String, Object?>) {
      throw PluginException('$name 详情返回格式异常');
    }

    final MagnetItem merged = _itemFromJson(root, fallback: item);
    final Object? filesValue = _valueAt(root, endpoint.filesPath);
    if (filesValue is! List<Object?>) {
      return merged;
    }

    return merged.copyWith(
      files: filesValue
          .whereType<Map<String, Object?>>()
          .map(_fileFromJson)
          .toList(growable: false),
    );
  }

  MagnetItem parseDetailHtml(MagnetItem item, String html) {
    final PluginEndpoint? endpoint = detail;
    if (endpoint == null || !endpoint.isHtml) {
      return item;
    }
    final List<Map<String, Object?>> roots = _htmlItems(html, endpoint);
    final MagnetItem merged = roots.isEmpty
        ? item
        : _itemFromJson(roots.first, fallback: item);
    return merged.copyWith(files: _htmlFiles(html, endpoint));
  }

  Uri? resolveDetailUrl(MagnetItem item) {
    final PluginEndpoint? endpoint = detail;
    if (endpoint == null) {
      return null;
    }
    return _resolveEndpoint(endpoint.url, _variablesForItem(item));
  }

  MagnetItem _itemFromJson(Map<String, Object?> json, {MagnetItem? fallback}) {
    final String infoHash = _field(
      json,
      'infoHash',
      fallback?.infoHash,
    ).toUpperCase();
    final Map<String, String> variables = <String, String>{
      'infoHash': infoHash,
      'infoHashLower': infoHash.toLowerCase(),
      'infoHashUpper': infoHash.toUpperCase(),
      'sourceItemId': _field(json, 'sourceItemId', fallback?.sourceItemId),
    };

    final String sourceItemId = variables['sourceItemId']!.isNotEmpty
        ? variables['sourceItemId']!
        : infoHash;
    variables['sourceItemId'] = sourceItemId;

    return MagnetItem(
      pluginId: id,
      pluginName: name,
      sourceItemId: sourceItemId,
      title: _field(json, 'title', fallback?.title),
      infoHash: infoHash,
      magnet: _fieldOrDefault(json, 'magnet', variables, fallback?.magnet),
      size: _intValue(_fieldRaw(json, 'size'), fallback?.size ?? 0),
      humanSize: _field(json, 'humanSize', fallback?.humanSize),
      seeders: _intValue(_fieldRaw(json, 'seeders'), fallback?.seeders ?? 0),
      leechers: _intValue(_fieldRaw(json, 'leechers'), fallback?.leechers ?? 0),
      score: _doubleValue(_fieldRaw(json, 'score'), fallback?.score ?? 0),
      health: _doubleValue(_fieldRaw(json, 'health'), fallback?.health ?? 0),
      verified: _boolValue(
        _fieldRaw(json, 'verified'),
        fallback?.verified ?? false,
      ),
      largestFile: _field(json, 'largestFile', fallback?.largestFile),
      webUrl: _absoluteUrl(
        _fieldOrDefault(json, 'webUrl', variables, fallback?.webUrl),
      ),
      createdAt:
          _dateValue(_fieldRaw(json, 'createdAt')) ?? fallback?.createdAt,
      lastSeen: _dateValue(_fieldRaw(json, 'lastSeen')) ?? fallback?.lastSeen,
      files: fallback?.files ?? const <MagnetFile>[],
    );
  }

  MagnetFile _fileFromJson(Map<String, Object?> json) {
    return MagnetFile(
      path: _fileField(json, 'path'),
      size: _intValue(_fileFieldRaw(json, 'size')),
      humanSize: _fileField(json, 'humanSize'),
    );
  }

  String _field(Map<String, Object?> json, String key, [String? fallback]) {
    final Object? value = _fieldRaw(json, key);
    if (value == null) {
      return fallback ?? '';
    }
    return value.toString();
  }

  Object? _fieldRaw(Map<String, Object?> json, String key) {
    final String? path = fields[key];
    if (path == null || path.isEmpty) {
      return null;
    }
    return _valueAt(json, path);
  }

  String _fieldOrDefault(
    Map<String, Object?> json,
    String key,
    Map<String, String> variables, [
    String? fallback,
  ]) {
    final String value = _field(json, key, fallback);
    if (value.isNotEmpty) {
      return value;
    }
    final String? template = defaults[key];
    if (template == null) {
      return fallback ?? '';
    }
    if (key == 'magnet' && (variables['infoHash'] ?? '').isEmpty) {
      return fallback ?? '';
    }
    return _applyTemplate(template, variables);
  }

  String _fileField(Map<String, Object?> json, String key) {
    final Object? value = _fileFieldRaw(json, key);
    return value?.toString() ?? '';
  }

  Object? _fileFieldRaw(Map<String, Object?> json, String key) {
    final String? path = fileFields[key];
    if (path == null || path.isEmpty) {
      return null;
    }
    return _valueAt(json, path);
  }

  Uri _resolveEndpoint(String pathTemplate, Map<String, String> variables) {
    final String path = _applyTemplate(pathTemplate, variables);
    final Uri parsed = Uri.parse(path);
    if (parsed.hasScheme) {
      return parsed;
    }
    return baseUrl.resolve(path);
  }

  Future<http.Response> _get(
    http.Client httpClient,
    PluginEndpoint endpoint,
    Map<String, String> variables,
    Map<String, String> extraHeaders,
  ) async {
    if (endpoint.method.toUpperCase() != 'GET') {
      throw PluginException('$name 暂只支持 GET 插件请求');
    }
    final Uri uri = _resolveEndpoint(endpoint.url, variables);
    try {
      return await httpClient
          .get(
            uri,
            headers: <String, String>{
              ...headers,
              ...endpoint.headers,
              ...extraHeaders,
            },
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw PluginException('$name 请求超时：$uri');
    } on SocketException catch (error) {
      throw PluginException('$name 网络连接失败：${error.message}：$uri');
    } on http.ClientException catch (error) {
      throw PluginException('$name HTTP 请求失败：$error');
    }
  }

  List<Map<String, Object?>> _htmlItems(String html, PluginEndpoint endpoint) {
    if (endpoint.itemPattern.isEmpty) {
      throw PluginException('$name HTML 插件缺少 itemPattern');
    }
    return _matchesAsMaps(
      _htmlScope(html, endpoint),
      endpoint.itemPattern,
      fields.values,
    );
  }

  List<MagnetFile> _htmlFiles(String html, PluginEndpoint endpoint) {
    if (endpoint.filePattern.isEmpty) {
      return const <MagnetFile>[];
    }
    return _matchesAsMaps(
      _htmlFileScope(html, endpoint),
      endpoint.filePattern,
      fileFields.values,
    ).map(_fileFromJson).toList(growable: false);
  }

  String _htmlScope(String html, PluginEndpoint endpoint) {
    if (endpoint.rootPattern.isEmpty) {
      return html;
    }
    final RegExpMatch? match = RegExp(
      endpoint.rootPattern,
      caseSensitive: false,
      dotAll: true,
      multiLine: true,
    ).firstMatch(html);
    return match?.group(1) ?? match?.group(0) ?? html;
  }

  String _htmlFileScope(String html, PluginEndpoint endpoint) {
    if (endpoint.fileRootPattern.isEmpty) {
      return _htmlScope(html, endpoint);
    }
    final RegExpMatch? match = RegExp(
      endpoint.fileRootPattern,
      caseSensitive: false,
      dotAll: true,
      multiLine: true,
    ).firstMatch(html);
    return match?.group(1) ?? match?.group(0) ?? _htmlScope(html, endpoint);
  }

  Map<String, String> _variablesForItem(MagnetItem item) {
    return <String, String>{
      'sourceItemId': item.sourceItemId,
      'infoHash': item.infoHash,
      'infoHashLower': item.infoHash.toLowerCase(),
      'infoHashUpper': item.infoHash.toUpperCase(),
    };
  }

  Map<String, String> _variablesForSearch({
    required String query,
    required int page,
  }) {
    final int page0 = page > 0 ? page - 1 : 0;
    return <String, String>{
      'query': query,
      'queryBase64': _base64NoPadding(query),
      'page': page.toString(),
      'page0': page0.toString(),
    };
  }

  String _absoluteUrl(String url) {
    if (url.isEmpty) {
      return '';
    }
    final Uri parsed = Uri.parse(url);
    if (parsed.hasScheme) {
      return url;
    }
    return baseUrl.resolve(url).toString();
  }

  void _throwIfHumanVerification(http.Response response) {
    if (!capabilities.requiresHumanVerification) {
      return;
    }
    if (!_looksLikeHumanVerification(response)) {
      return;
    }
    throw PluginHumanVerificationException(
      '$name requires human verification before retrying.',
      verificationUrl: response.request?.url ?? baseUrl,
    );
  }
}

class PluginCapabilities {
  const PluginCapabilities({required this.requiresHumanVerification});

  final bool requiresHumanVerification;

  factory PluginCapabilities.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return const PluginCapabilities(requiresHumanVerification: false);
    }
    return PluginCapabilities(
      requiresHumanVerification: _boolValue(json['requiresHumanVerification']),
    );
  }
}

class PluginEndpoint {
  const PluginEndpoint({
    required this.method,
    required this.url,
    required this.responseType,
    required this.headers,
    required this.itemsPath,
    required this.totalPath,
    required this.currentPagePath,
    required this.lastPagePath,
    required this.rootPath,
    required this.filesPath,
    required this.rootPattern,
    required this.itemPattern,
    required this.fileRootPattern,
    required this.filePattern,
    required this.totalPattern,
    required this.lastPagePattern,
    required this.pageSize,
  });

  final String method;
  final String url;
  final String responseType;
  final Map<String, String> headers;
  final String itemsPath;
  final String totalPath;
  final String currentPagePath;
  final String lastPagePath;
  final String rootPath;
  final String filesPath;
  final String rootPattern;
  final String itemPattern;
  final String fileRootPattern;
  final String filePattern;
  final String totalPattern;
  final String lastPagePattern;
  final int pageSize;

  bool get isHtml => responseType.toLowerCase() == 'html';

  factory PluginEndpoint.fromJson(Map<String, Object?> json) {
    return PluginEndpoint(
      method: _stringValue(json['method'], 'GET'),
      url: _stringValue(json['url']),
      responseType: _stringValue(json['responseType'], 'json'),
      headers: _stringMap(json['headers']),
      itemsPath: _stringValue(json['itemsPath']),
      totalPath: _stringValue(json['totalPath']),
      currentPagePath: _stringValue(json['currentPagePath']),
      lastPagePath: _stringValue(json['lastPagePath']),
      rootPath: _stringValue(json['rootPath']),
      filesPath: _stringValue(json['filesPath']),
      rootPattern: _stringValue(json['rootPattern']),
      itemPattern: _stringValue(json['itemPattern']),
      fileRootPattern: _stringValue(json['fileRootPattern']),
      filePattern: _stringValue(json['filePattern']),
      totalPattern: _stringValue(json['totalPattern']),
      lastPagePattern: _stringValue(json['lastPagePattern']),
      pageSize: _intValue(json['pageSize'], 20),
    );
  }
}

class JsonPluginRegistry {
  JsonPluginRegistry({http.Client? client})
    : _client = client ?? _createDefaultHttpClient();

  final http.Client _client;
  final Map<String, String> _cookiesByHost = <String, String>{};

  Future<List<JsonSourcePlugin>> loadInstalledPlugins() async {
    final Directory directory = await pluginsDirectory();
    final List<FileSystemEntity> entries = await directory
        .list()
        .where((FileSystemEntity entity) => entity is File)
        .toList();
    entries.sort(
      (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
    );

    final List<JsonSourcePlugin> plugins = <JsonSourcePlugin>[];
    for (final FileSystemEntity entity in entries) {
      if (!entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final String raw = await File(entity.path).readAsString();
        plugins.add(parsePluginJson(raw));
      } on Object {
        // Keep one broken local plugin from blocking the whole app.
      }
    }
    return plugins;
  }

  Future<Directory> pluginsDirectory() {
    return AppStorage.ensureSubdirectory('plugins');
  }

  Future<JsonSourcePlugin> savePluginJson(
    String raw, {
    String? replacingId,
  }) async {
    final JsonSourcePlugin plugin = parsePluginJson(raw);
    final Directory directory = await pluginsDirectory();
    if (replacingId != null &&
        replacingId.isNotEmpty &&
        replacingId != plugin.id) {
      final File previous = _pluginFile(directory, replacingId);
      if (await previous.exists()) {
        await previous.delete();
      }
    }
    final File file = _pluginFile(directory, plugin.id);
    await file.writeAsString(_prettyPluginJson(raw));
    return plugin;
  }

  Future<void> deletePlugin(String pluginId) async {
    final Directory directory = await pluginsDirectory();
    final File file = _pluginFile(directory, pluginId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String> readPluginJson(String pluginId) async {
    final Directory directory = await pluginsDirectory();
    final File file = _pluginFile(directory, pluginId);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<PluginSearchResult> search(
    JsonSourcePlugin plugin, {
    required String query,
    required int page,
  }) {
    return plugin.runSearch(
      query: query,
      page: page,
      client: _client,
      extraHeaders: _extraHeadersFor(plugin),
    );
  }

  Future<MagnetItem> details(JsonSourcePlugin plugin, MagnetItem item) {
    return plugin.runDetail(
      item,
      client: _client,
      extraHeaders: _extraHeadersFor(plugin),
    );
  }

  void setVerificationCookie(JsonSourcePlugin plugin, String cookie) {
    final String normalized = _normalizeCookie(cookie);
    if (normalized.isEmpty) {
      return;
    }
    _cookiesByHost[plugin.baseUrl.host] = normalized;
  }

  Map<String, String> _extraHeadersFor(JsonSourcePlugin plugin) {
    final String? cookie = _cookiesByHost[plugin.baseUrl.host];
    if (cookie == null || cookie.isEmpty) {
      return const <String, String>{};
    }
    return <String, String>{'Cookie': cookie};
  }
}

http.Client _createDefaultHttpClient() {
  final HttpClient httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 20);

  final String proxyRule = _proxyRule();
  if (proxyRule != 'DIRECT') {
    httpClient.findProxy = (_) => proxyRule;
  }

  return IOClient(httpClient);
}

String _proxyRule() {
  final _ProxyAddress? configured = _proxyFromEnvironment();
  if (configured != null) {
    return 'PROXY ${configured.host}:${configured.port}; DIRECT';
  }

  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return 'DIRECT';
  }

  const List<int> commonHttpProxyPorts = <int>[
    7890,
    7897,
    7899,
    10809,
    10808,
    8080,
  ];
  for (final int port in commonHttpProxyPorts) {
    if (_isPortOpen('127.0.0.1', port)) {
      return 'PROXY 127.0.0.1:$port; DIRECT';
    }
  }

  return 'DIRECT';
}

_ProxyAddress? _proxyFromEnvironment() {
  final String? raw = _environmentValue(<String>[
    'JAVBUS_PROXY',
    'HTTPS_PROXY',
    'HTTP_PROXY',
    'ALL_PROXY',
  ]);
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }

  final String value = raw.trim();
  final Uri? uri = Uri.tryParse(
    value.contains('://') ? value : 'http://$value',
  );
  if (uri == null || uri.host.isEmpty || uri.port == 0) {
    return null;
  }
  if (uri.scheme.toLowerCase().startsWith('socks')) {
    return null;
  }
  return _ProxyAddress(uri.host, uri.port);
}

String? _environmentValue(List<String> keys) {
  for (final String key in keys) {
    final String? exact = Platform.environment[key];
    if (exact != null) {
      return exact;
    }
  }

  final Set<String> lowerKeys = keys
      .map((String key) => key.toLowerCase())
      .toSet();
  for (final MapEntry<String, String> entry in Platform.environment.entries) {
    if (lowerKeys.contains(entry.key.toLowerCase())) {
      return entry.value;
    }
  }
  return null;
}

bool _isPortOpen(String host, int port) {
  try {
    final RawSynchronousSocket socket = RawSynchronousSocket.connectSync(
      host,
      port,
    );
    socket.closeSync();
    return true;
  } on Object {
    return false;
  }
}

class _ProxyAddress {
  const _ProxyAddress(this.host, this.port);

  final String host;
  final int port;
}

class PluginException implements Exception {
  const PluginException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PluginHumanVerificationException extends PluginException {
  const PluginHumanVerificationException(
    super.message, {
    required this.verificationUrl,
  });

  final Uri verificationUrl;
}

JsonSourcePlugin parsePluginJson(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw const PluginException('插件 JSON 顶层必须是对象');
  }
  final JsonSourcePlugin plugin = JsonSourcePlugin.fromJson(decoded);
  if (plugin.id.trim().isEmpty) {
    throw const PluginException('插件缺少 id');
  }
  if (plugin.name.trim().isEmpty) {
    throw const PluginException('插件缺少 name');
  }
  if (!plugin.baseUrl.hasScheme || plugin.baseUrl.host.isEmpty) {
    throw const PluginException('插件 baseUrl 必须是完整 URL');
  }
  return plugin;
}

File _pluginFile(Directory directory, String pluginId) {
  return File(
    '${directory.path}${Platform.pathSeparator}${_safePluginFileName(pluginId)}.json',
  );
}

String _safePluginFileName(String value) {
  final String safe = value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (safe.isNotEmpty) {
    return safe;
  }
  return DateTime.now().microsecondsSinceEpoch.toString();
}

String _prettyPluginJson(String raw) {
  final Object? decoded = jsonDecode(raw);
  return const JsonEncoder.withIndent('  ').convert(decoded);
}

String _normalizeCookie(String cookie) {
  var value = cookie.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  return value.trim();
}

bool _looksLikeHumanVerification(http.Response response) {
  if (response.statusCode == 403 || response.statusCode == 503) {
    return true;
  }

  final String body = response.body.toLowerCase();
  return body.contains('cf-chl') ||
      body.contains('challenge-platform') ||
      body.contains('enable javascript and cookies') ||
      body.contains('just a moment') ||
      body.contains('cloudflare');
}

String _applyTemplate(String template, Map<String, String> variables) {
  var result = template;
  for (final MapEntry<String, String> entry in variables.entries) {
    result = result.replaceAll(
      '{${entry.key}}',
      Uri.encodeComponent(entry.value),
    );
  }
  return result;
}

String _base64NoPadding(String value) {
  return base64Url.encode(utf8.encode(value)).replaceAll(RegExp(r'=+$'), '');
}

List<Map<String, Object?>> _matchesAsMaps(
  String input,
  String pattern,
  Iterable<String> targetPaths,
) {
  final RegExp regex = RegExp(
    pattern,
    caseSensitive: false,
    dotAll: true,
    multiLine: true,
  );
  final bool usesNamedGroups = pattern.contains('?<');
  return regex
      .allMatches(input)
      .map((RegExpMatch match) {
        final Map<String, Object?> item = <String, Object?>{};
        var index = 1;
        for (final String targetPath in targetPaths) {
          if (targetPath.isEmpty) {
            continue;
          }
          final String? named = _namedGroup(
            match,
            _lastPathSegment(targetPath),
          );
          if (usesNamedGroups) {
            if (named != null) {
              _setValueAt(item, targetPath, _cleanHtml(named));
            }
            continue;
          }
          final String? indexed = index <= match.groupCount
              ? match.group(index)
              : null;
          _setValueAt(item, targetPath, _cleanHtml(named ?? indexed ?? ''));
          index++;
        }
        return item;
      })
      .toList(growable: false);
}

int _firstIntMatch(String input, String pattern, int fallback) {
  if (pattern.isEmpty) {
    return fallback;
  }
  final RegExpMatch? match = RegExp(
    pattern,
    caseSensitive: false,
    dotAll: true,
    multiLine: true,
  ).firstMatch(input);
  if (match == null) {
    return fallback;
  }
  return int.tryParse(match.group(1) ?? '') ?? fallback;
}

String? _namedGroup(RegExpMatch match, String name) {
  try {
    return match.namedGroup(name);
  } on ArgumentError {
    return null;
  }
}

String _lastPathSegment(String path) {
  if (!path.contains('.')) {
    return path;
  }
  return path.split('.').last;
}

void _setValueAt(Map<String, Object?> target, String path, Object? value) {
  final List<String> parts = path.split('.');
  Map<String, Object?> current = target;
  for (final String part in parts.take(parts.length - 1)) {
    final Object? child = current[part];
    if (child is Map<String, Object?>) {
      current = child;
    } else {
      final Map<String, Object?> next = <String, Object?>{};
      current[part] = next;
      current = next;
    }
  }
  current[parts.last] = value;
}

String _cleanHtml(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#160;', ' ')
      .replaceAll('&#xA0;', ' ')
      .replaceAll('\u00A0', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Object? _valueAt(Object? root, String path) {
  if (path.isEmpty) {
    return root;
  }
  Object? current = root;
  for (final String part in path.split('.')) {
    if (current is Map<String, Object?>) {
      current = current[part];
    } else if (current is List<Object?>) {
      final int? index = int.tryParse(part);
      current = index == null || index < 0 || index >= current.length
          ? null
          : current[index];
    } else {
      return null;
    }
  }
  return current;
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map<String, Object?>) {
    return const <String, String>{};
  }
  return value.map(
    (String key, Object? raw) => MapEntry<String, String>(key, raw.toString()),
  );
}

String _stringValue(Object? value, [String fallback = '']) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int _intValue(Object? value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

double _doubleValue(Object? value, [double fallback = 0]) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? fallback;
  }
  return fallback;
}

bool _boolValue(Object? value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return fallback;
}

DateTime? _dateValue(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

int _lastPageFromTotal(int total, int pageSize) {
  if (total <= 0 || pageSize <= 0) {
    return 1;
  }
  return (total / pageSize).ceil();
}
