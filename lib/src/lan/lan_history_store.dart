import 'dart:convert';
import 'dart:io';

import '../settings/app_settings.dart';
import '../storage/app_storage.dart';
import 'lan_models.dart';

class LanHistoryStore {
  LanHistoryStore({AppSettingsStore? settingsStore})
    : _settingsStore = settingsStore ?? AppSettingsStore();

  static const int maxRecords = 200;

  final AppSettingsStore _settingsStore;

  Future<List<LanTransferRecord>> load() async {
    final File file = await _historyFile();
    if (!await file.exists()) {
      return const <LanTransferRecord>[];
    }
    final String raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const <LanTransferRecord>[];
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) {
      return const <LanTransferRecord>[];
    }
    return decoded
        .whereType<Map<String, Object?>>()
        .map(LanTransferRecord.fromJson)
        .toList(growable: false);
  }

  Future<void> add(LanTransferRecord record) async {
    final List<LanTransferRecord> records = <LanTransferRecord>[
      record,
      ...await load(),
    ];
    await save(records.take(maxRecords).toList(growable: false));
  }

  Future<void> save(List<LanTransferRecord> records) async {
    final File file = await _historyFile();
    await file.writeAsString(
      encodeLanJson(
        records.map((LanTransferRecord item) => item.toJson()).toList(),
      ),
    );
  }

  Future<void> clear() async {
    final File file = await _historyFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> receivedDirectory() async {
    final AppSettings settings = await _settingsStore.load();
    final String configuredPath = settings.lanReceiveDirectory.trim();
    if (configuredPath.isNotEmpty) {
      final Directory configured = Directory(configuredPath);
      try {
        if (!await configured.exists()) {
          await configured.create(recursive: true);
        }
        final File probe = File(
          '${configured.path}${Platform.pathSeparator}.javbus_write_test',
        );
        await probe.writeAsString('ok');
        await probe.delete();
        return configured;
      } on Object {
        // Fall back to the private app directory when the configured path is unavailable.
      }
    }
    return AppStorage.ensureSubdirectory('lan/received');
  }

  Future<File> _historyFile() async {
    final Directory directory = await AppStorage.ensureSubdirectory('lan');
    return File('${directory.path}${Platform.pathSeparator}history.json');
  }
}
