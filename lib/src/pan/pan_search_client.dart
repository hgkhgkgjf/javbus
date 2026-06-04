import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../settings/app_settings.dart';

class PanSearchClient {
  PanSearchClient({http.Client? client, AppSettingsStore? settingsStore})
    : _client = client,
      _settingsStore = settingsStore ?? AppSettingsStore();

  http.Client? _client;
  final AppSettingsStore _settingsStore;

  http.Client get _httpClient {
    return _client ??= _createDefaultHttpClient();
  }

  Future<PanHealth> health() async {
    final AppSettings settings = await _settingsStore.load();
    final Uri baseUrl = _baseUrlFromSettings(settings);
    final Uri uri = baseUrl.resolve('/api/health');
    final http.Response response = await _getWithSpaceWakeup(
      uri,
      settings,
      requestTimeout: const Duration(seconds: 15),
    );
    if (response.statusCode != 200) {
      throw PanSearchException('搜盘服务状态检查失败：HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw const PanSearchException('搜盘服务状态返回格式异常');
    }
    return PanHealth.fromJson(decoded);
  }

  Future<PanSearchResult> search({required String keyword}) async {
    final AppSettings settings = await _settingsStore.load();
    final Uri baseUrl = _baseUrlFromSettings(settings);
    final Map<String, String> query = <String, String>{
      'kw': keyword,
      'res': 'merge',
      'src': 'all',
    };
    final Uri uri = baseUrl.replace(
      path: '/api/search',
      queryParameters: query,
    );
    try {
      final http.Response response = await _getWithSpaceWakeup(
        uri,
        settings,
        requestTimeout: const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw PanSearchException('搜盘失败：HTTP ${response.statusCode}');
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const PanSearchException('搜盘返回格式异常');
      }
      return PanSearchResult.fromJson(decoded);
    } on TimeoutException {
      throw const PanSearchException('搜盘请求超时');
    } on SocketException catch (error) {
      throw PanSearchException('搜盘网络连接失败：${error.message}');
    } on FormatException {
      throw const PanSearchException('搜盘返回不是有效 JSON');
    }
  }

  Uri _baseUrlFromSettings(AppSettings settings) {
    final String raw = settings.panServiceUrl.trim();
    if (raw.isEmpty) {
      throw const PanSearchException('请先在设置里填写盘搜服务地址');
    }
    final Uri? uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const PanSearchException('盘搜服务地址无效');
    }
    return uri;
  }

  Map<String, String> _headersFor(AppSettings settings) {
    if (!settings.panRequiresApiKey) {
      return const <String, String>{};
    }
    final String key = settings.panApiKey.trim();
    if (key.isEmpty) {
      throw const PanSearchException('盘搜服务已启用密钥，请先在设置里填写密钥');
    }
    return <String, String>{
      'Authorization': key.toLowerCase().startsWith('bearer ')
          ? key
          : 'Bearer $key',
    };
  }

  Future<http.Response> _getWithSpaceWakeup(
    Uri uri,
    AppSettings settings, {
    required Duration requestTimeout,
  }) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 90));
    while (true) {
      final http.Response response = await _httpClient
          .get(uri, headers: _headersFor(settings))
          .timeout(requestTimeout);
      if (!_looksLikeHuggingFacePreparing(response)) {
        return response;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const PanSearchException('盘搜服务正在唤醒，请稍后再试');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}

class PanHealth {
  const PanHealth({required this.message, required this.raw});

  final String message;
  final Map<String, Object?> raw;

  factory PanHealth.fromJson(Map<String, Object?> json) {
    return PanHealth(message: _stringValue(json['message'], 'ok'), raw: json);
  }
}

class PanSearchResult {
  const PanSearchResult({
    required this.total,
    required this.groups,
    required this.message,
  });

  final int total;
  final List<PanResultGroup> groups;
  final String message;

  factory PanSearchResult.fromJson(Map<String, Object?> json) {
    final int code = _intValue(json['code']);
    final String message = _stringValue(json['message']);
    if (code != 0) {
      throw PanSearchException(message.isEmpty ? '搜盘服务返回错误：$code' : message);
    }

    final Object? data = json['data'];
    if (data is! Map<String, Object?>) {
      throw const PanSearchException('搜盘返回缺少 data');
    }
    final Object? merged = data['merged_by_type'];
    if (merged is! Map<String, Object?>) {
      return PanSearchResult(
        total: _intValue(data['total']),
        groups: const <PanResultGroup>[],
        message: message,
      );
    }

    final List<PanResultGroup> groups = <PanResultGroup>[];
    for (final MapEntry<String, Object?> entry in merged.entries) {
      final Object? rawItems = entry.value;
      if (rawItems is! List<Object?>) {
        continue;
      }
      final List<PanShareItem> items = rawItems
          .whereType<Map<String, Object?>>()
          .map(
            (Map<String, Object?> item) =>
                PanShareItem.fromJson(cloudType: entry.key, json: item),
          )
          .where((PanShareItem item) => item.url.isNotEmpty)
          .toList(growable: false);
      if (items.isNotEmpty) {
        groups.add(PanResultGroup(cloudType: entry.key, items: items));
      }
    }

    groups.sort(
      (PanResultGroup a, PanResultGroup b) =>
          b.items.length.compareTo(a.items.length),
    );
    return PanSearchResult(
      total: _intValue(data['total']),
      groups: groups,
      message: message,
    );
  }
}

class PanResultGroup {
  const PanResultGroup({required this.cloudType, required this.items});

  final String cloudType;
  final List<PanShareItem> items;
}

class PanShareItem {
  const PanShareItem({
    required this.cloudType,
    required this.url,
    required this.password,
    required this.note,
    required this.datetime,
    required this.source,
  });

  final String cloudType;
  final String url;
  final String password;
  final String note;
  final DateTime? datetime;
  final String source;

  String get title => note.isNotEmpty ? note : url;

  factory PanShareItem.fromJson({
    required String cloudType,
    required Map<String, Object?> json,
  }) {
    return PanShareItem(
      cloudType: cloudType,
      url: _stringValue(json['url']),
      password: _stringValue(json['password']),
      note: _stringValue(json['note']),
      datetime: DateTime.tryParse(_stringValue(json['datetime'])),
      source: _stringValue(json['source']),
    );
  }
}

class PanSearchException implements Exception {
  const PanSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _stringValue(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
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

bool _looksLikeHuggingFacePreparing(http.Response response) {
  if (response.statusCode != 206 && response.statusCode != 503) {
    return false;
  }
  final String body = response.body.toLowerCase();
  return body.contains('preparing space') ||
      body.contains('hugging face') ||
      body.contains('huggingface.co/spaces');
}
