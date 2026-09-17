import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// What a mushaf line renders, from `quran.db`'s `lines.line_type`.
enum LineType {
  /// A surah's name header. Carries [MushafLine.surahNumber]; no words.
  surahName('surah_name'),

  /// The Bismillah, set on its own line ahead of a surah's first ayah.
  /// Carries [MushafLine.surahNumber]; no words.
  basmala('basmallah'),

  /// Ordinary Quranic text. Carries a word range, not a surah number.
  ayah('ayah');

  const LineType(this.dbValue);

  final String dbValue;

  static LineType fromDb(String value, {required int page, required int line}) {
    for (final LineType type in LineType.values) {
      if (type.dbValue == value) return type;
    }
    throw CatalogValidationException(
      'quran.db',
      'Line $page:$line has unknown line_type "$value".',
    );
  }
}

/// One row of `quran.db`'s `lines` table — a single printed line of the
/// mushaf, at a fixed page and line position.
///
/// A surah-name or basmala line carries [surahNumber] and no word range; an
/// ayah line carries a word range ([firstWordId]..[lastWordId]) and no
/// surah number. The database stores the unused side as an empty string
/// rather than SQL `NULL`, so both are surfaced here as nullable ints and
/// parsed leniently.
class MushafLine extends Equatable {
  const MushafLine({
    required this.page,
    required this.line,
    required this.lineType,
    required this.isCentered,
    required this.surahNumber,
    required this.firstWordId,
    required this.lastWordId,
  });

  final int page;
  final int line;
  final LineType lineType;
  final bool isCentered;

  /// Set for [LineType.surahName] and [LineType.basmala] lines, null for
  /// [LineType.ayah] lines.
  final int? surahNumber;

  /// Set for [LineType.ayah] lines, null otherwise. Inclusive word-id range
  /// into `quran.db`'s `words` table.
  final int? firstWordId;
  final int? lastWordId;

  factory MushafLine.fromRow(Map<String, Object?> row) {
    final int page = row['page']! as int;
    final int line = row['line']! as int;
    return MushafLine(
      page: page,
      line: line,
      lineType: LineType.fromDb(
        row['line_type']! as String,
        page: page,
        line: line,
      ),
      isCentered: (row['is_centered']! as int) != 0,
      surahNumber: _intOrNull(row['surah_number']),
      firstWordId: _intOrNull(row['first_word_id']),
      lastWordId: _intOrNull(row['last_word_id']),
    );
  }

  /// `quran.db` stores an unused int column as `''` rather than `NULL`.
  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return value.isEmpty ? null : int.parse(value);
    throw ArgumentError('Unexpected value for a nullable int column: $value');
  }

  @override
  List<Object?> get props => <Object?>[
    page,
    line,
    lineType,
    isCentered,
    surahNumber,
    firstWordId,
    lastWordId,
  ];
}
