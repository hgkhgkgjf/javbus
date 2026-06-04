import 'dart:convert';
import 'dart:io';

import '../storage/app_storage.dart';

class AppSettings {
  const AppSettings({
    required this.panServiceUrl,
    required this.panRequiresApiKey,
    required this.panApiKey,
  });

  final String panServiceUrl;
  final bool panRequiresApiKey;
  final String panApiKey;

  bool get hasPanService => panServiceUrl.trim().isNotEmpty;

  AppSettings copyWith({
    String? panServiceUrl,
    bool? panRequiresApiKey,
    String? panApiKey,
  }) {
    return AppSettings(
      panServiceUrl: panServiceUrl ?? this.panServiceUrl,
      panRequiresApiKey: panRequiresApiKey ?? this.panRequiresApiKey,
      panApiKey: panApiKey ?? this.panApiKey,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'panServiceUrl': panServiceUrl,
      'panRequiresApiKey': panRequiresApiKey,
      'panApiKey': panApiKey,
    };
  }

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      panServiceUrl: _stringValue(json['panServiceUrl']),
      panRequiresApiKey: _boolValue(json['panRequiresApiKey']),
      panApiKey: _stringValue(json['panApiKey']),
    );
  }

  static const AppSettings empty = AppSettings(
    panServiceUrl: '',
    panRequiresApiKey: false,
    panApiKey: '',
  );
}

class AppSettingsStore {
  Future<AppSettings> load() async {
    final File file = await _file();
    if (!await file.exists()) {
      return AppSettings.empty;
    }
    final String raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return AppSettings.empty;
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return AppSettings.empty;
    }
    return AppSettings.fromJson(decoded);
  }

  Future<void> save(AppSettings settings) async {
    final File file = await _file();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  Future<File> _file() async {
    final Directory directory = await AppStorage.ensureSubdirectory('settings');
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }
}

String _stringValue(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
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
