class MagnetItem {
  const MagnetItem({
    required this.pluginId,
    required this.pluginName,
    required this.sourceItemId,
    required this.title,
    required this.infoHash,
    required this.magnet,
    required this.size,
    required this.humanSize,
    required this.seeders,
    required this.leechers,
    required this.score,
    required this.health,
    required this.verified,
    required this.largestFile,
    required this.webUrl,
    required this.createdAt,
    required this.lastSeen,
    this.files = const <MagnetFile>[],
  });

  final String pluginId;
  final String pluginName;
  final String sourceItemId;
  final String title;
  final String infoHash;
  final String magnet;
  final int size;
  final String humanSize;
  final int seeders;
  final int leechers;
  final double score;
  final double health;
  final bool verified;
  final String largestFile;
  final String webUrl;
  final DateTime? createdAt;
  final DateTime? lastSeen;
  final List<MagnetFile> files;

  String get displaySize =>
      humanSize.isNotEmpty ? humanSize : formatBytes(size);
  bool get hasDetails => files.isNotEmpty;
  String get stableKey => sourceItemId.isNotEmpty ? sourceItemId : infoHash;

  MagnetItem copyWith({List<MagnetFile>? files}) {
    return MagnetItem(
      pluginId: pluginId,
      pluginName: pluginName,
      sourceItemId: sourceItemId,
      title: title,
      infoHash: infoHash,
      magnet: magnet,
      size: size,
      humanSize: humanSize,
      seeders: seeders,
      leechers: leechers,
      score: score,
      health: health,
      verified: verified,
      largestFile: largestFile,
      webUrl: webUrl,
      createdAt: createdAt,
      lastSeen: lastSeen,
      files: files ?? this.files,
    );
  }
}

class MagnetFile {
  const MagnetFile({
    required this.path,
    required this.size,
    required this.humanSize,
  });

  final String path;
  final int size;
  final String humanSize;

  String get displaySize =>
      humanSize.isNotEmpty ? humanSize : formatBytes(size);
}

class PluginSearchResult {
  const PluginSearchResult({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });

  final List<MagnetItem> items;
  final int currentPage;
  final int lastPage;
  final int total;
}

String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[index]}';
}
