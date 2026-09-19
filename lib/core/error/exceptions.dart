/// Thrown by data sources. Repositories catch these and map them to a
/// `Failure` (CLAUDE.md A.3, Errors).
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// An asset declared in the catalog is missing from the bundle.
class AssetNotFoundException extends AppException {
  const AssetNotFoundException(this.assetPath, String message) : super(message);

  final String assetPath;
}

/// An asset exists but is not the JSON shape the contract describes.
class AssetParseException extends AppException {
  const AssetParseException(this.assetPath, String message) : super(message);

  final String assetPath;
}

/// An asset parses, but its contents contradict the catalog — a wrong ayah
/// count, a duplicate number, a gap in the sequence. Never repaired silently
/// (CLAUDE.md A.2 rule 1).
class CatalogValidationException extends AppException {
  const CatalogValidationException(this.assetPath, String message)
    : super(message);

  final String assetPath;
}

/// A session configuration cannot produce a plan.
class SessionConfigException extends AppException {
  const SessionConfigException(super.message);
}

/// Local storage could not be read or written.
class StorageException extends AppException {
  const StorageException(super.message);
}

/// A tool the admin pipeline shells out to is not installed.
class ToolMissingException extends AppException {
  const ToolMissingException(this.tool, String message) : super(message);

  final String tool;
}

/// A local processing step — splitting, encoding — failed.
class ProcessingException extends AppException {
  const ProcessingException(this.path, String message) : super(message);

  final String path;
}

/// An upload to the CDN failed, or was refused.
class UploadException extends AppException {
  const UploadException(this.key, String message) : super(message);

  /// The object key, never the credentials that signed for it.
  final String key;
}

/// An audio pack could not be downloaded, verified or installed.
///
/// Separate from [StorageException] because the cause is usually the network
/// or the CDN's own bytes rather than the device, and separate from the quiet
/// degrade of CLAUDE.md A.2 rule 3 because a download is something the user
/// asked for by name: it is allowed to report that it failed.
class DownloadException extends AppException {
  const DownloadException(this.source, String message) : super(message);

  /// What was being fetched or opened — a url or a file path.
  final String source;
}
