import 'package:equatable/equatable.dart';

import 'exceptions.dart';

/// The left side of every repository result.
sealed class Failure extends Equatable {
  const Failure(this.message);

  /// Developer-facing detail. User-facing copy comes from the translation
  /// files, keyed off the failure type — never from this string.
  final String message;

  @override
  List<Object?> get props => <Object?>[message];
}

/// A required asset is missing from the bundle.
class AssetNotFoundFailure extends Failure {
  const AssetNotFoundFailure(this.assetPath, super.message);

  final String assetPath;

  @override
  List<Object?> get props => <Object?>[assetPath, message];
}

/// An asset could not be parsed into the shape the data contract describes.
class AssetParseFailure extends Failure {
  const AssetParseFailure(this.assetPath, super.message);

  final String assetPath;

  @override
  List<Object?> get props => <Object?>[assetPath, message];
}

/// An asset's contents contradict the catalog.
class CatalogValidationFailure extends Failure {
  const CatalogValidationFailure(this.assetPath, super.message);

  final String assetPath;

  @override
  List<Object?> get props => <Object?>[assetPath, message];
}

/// A session configuration cannot produce a plan — an inverted range, a
/// repeat count out of bounds, ayahs beyond the end of the surah.
class SessionConfigFailure extends Failure {
  const SessionConfigFailure(super.message);
}

/// Local storage failed.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// A tool the admin pipeline needs is not installed.
class ToolMissingFailure extends Failure {
  const ToolMissingFailure(this.tool, super.message);

  final String tool;

  @override
  List<Object?> get props => <Object?>[tool, message];
}

/// A local processing step failed.
class ProcessingFailure extends Failure {
  const ProcessingFailure(this.path, super.message);

  final String path;

  @override
  List<Object?> get props => <Object?>[path, message];
}

/// An upload to the CDN failed, or was refused.
class UploadFailure extends Failure {
  const UploadFailure(this.key, super.message);

  final String key;

  @override
  List<Object?> get props => <Object?>[key, message];
}

/// An audio pack could not be downloaded, verified or installed.
class DownloadFailure extends Failure {
  const DownloadFailure(this.source, super.message);

  /// What was being fetched or opened — a url or a file path.
  final String source;

  @override
  List<Object?> get props => <Object?>[source, message];
}

/// Maps a data-source exception onto its failure. Kept in one place so every
/// repository translates the same way.
Failure failureFromException(AppException e) => switch (e) {
  AssetNotFoundException() => AssetNotFoundFailure(e.assetPath, e.message),
  AssetParseException() => AssetParseFailure(e.assetPath, e.message),
  CatalogValidationException() => CatalogValidationFailure(
    e.assetPath,
    e.message,
  ),
  SessionConfigException() => SessionConfigFailure(e.message),
  StorageException() => StorageFailure(e.message),
  DownloadException() => DownloadFailure(e.source, e.message),
  ToolMissingException() => ToolMissingFailure(e.tool, e.message),
  ProcessingException() => ProcessingFailure(e.path, e.message),
  UploadException() => UploadFailure(e.key, e.message),
};
