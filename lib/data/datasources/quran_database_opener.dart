import 'package:sqflite_common/sqlite_api.dart';

/// Hands out the open `quran.db`.
///
/// Flutter-free on purpose: the app's implementation (`QuranDatabase`) copies
/// the asset out of the bundle, but the catalog loaders only need an open
/// database, so a plain `dart run` tool or a test can hand them one directly.
abstract interface class QuranDatabaseOpener {
  Future<Database> open();
}
