import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract final class AppStorage {
  static Future<Directory> rootDirectory() async {
    final String? appData = Platform.environment['APPDATA'];
    if (Platform.isWindows && appData != null && appData.isNotEmpty) {
      return Directory('$appData\\JavBusMagnetFinder');
    }

    if (Platform.isAndroid) {
      return getApplicationSupportDirectory();
    }

    final String? home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.javbus_magnet_finder');
    }

    try {
      return getApplicationSupportDirectory();
    } on Object {
      return Directory(
        '${Directory.current.path}${Platform.pathSeparator}data',
      );
    }
  }

  static Future<Directory> ensureSubdirectory(String name) async {
    final Directory root = await rootDirectory();
    final Directory directory = Directory(
      '${root.path}${Platform.pathSeparator}$name',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
}
