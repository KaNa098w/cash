class AppUpdateResponse {
  final bool updateAvailable;
  final String latestVersion;
  final String channel;
  final String packageType;
  final String downloadUrl;
  final String checksumSha256;
  final int fileSize;
  final String releaseNotes;
  final DateTime? publishedAt;
  final bool isMandatory;

  AppUpdateResponse({
    required this.updateAvailable,
    required this.latestVersion,
    required this.channel,
    required this.packageType,
    required this.downloadUrl,
    required this.checksumSha256,
    required this.fileSize,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMandatory,
  });

  factory AppUpdateResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    if (rawData is! Map<String, dynamic>) {
      throw Exception('Invalid app update response format: expected "data" object.');
    }

    return AppUpdateResponse(
      updateAvailable: rawData['update_available'] == true,
      latestVersion: (rawData['latest_version'] ?? '').toString().trim(),
      channel: (rawData['channel'] ?? '').toString().trim(),
      packageType: (rawData['package_type'] ?? '').toString().trim(),
      downloadUrl: (rawData['download_url'] ?? '').toString().trim(),
      checksumSha256: (rawData['checksum_sha256'] ?? '').toString().trim(),
      fileSize: (rawData['file_size'] as num?)?.toInt() ?? 0,
      releaseNotes: (rawData['release_notes'] ?? '').toString(),
      publishedAt: _parseDate(rawData['published_at']),
      isMandatory: rawData['is_mandatory'] == true,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
