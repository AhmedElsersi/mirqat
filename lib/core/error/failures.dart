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

/// Local storage failed.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
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
  StorageException() => StorageFailure(e.message),
};
