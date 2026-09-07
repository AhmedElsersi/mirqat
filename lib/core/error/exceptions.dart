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
  const AssetNotFoundException(this.assetPath, String message)
    : super(message);

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

/// Local storage could not be read or written.
class StorageException extends AppException {
  const StorageException(super.message);
}
