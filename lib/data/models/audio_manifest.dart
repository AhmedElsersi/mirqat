import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// One surah's pack at one bitrate: what to expect before unzipping it.
class PackVariant extends Equatable {
  const PackVariant({
    required this.bitrate,
    required this.bytes,
    required this.sha256,
  });

  final int bitrate;

  /// Pack size in bytes. Checked before the digest — a truncated download is
  /// the common failure, and length is the cheap way to catch it.
  final int bytes;
  final String sha256;

  @override
  List<Object?> get props => <Object?>[bitrate, bytes, sha256];
}

/// One surah a manifest reciter has recorded.
class ManifestSurah extends Equatable {
  const ManifestSurah({
    required this.number,
    required this.ayahs,
    required this.bytes,
    required this.sha256,
    this.hasBasmala,
    this.qualities = const <int, PackVariant>{},
  });

  final int number;

  /// Ayah count the recording was cut to. Checked against quran.db before the
  /// surah is offered, so audio can never be played against the wrong ayah.
  final int ayahs;

  /// Pack size and digest, for verifying a download.
  final int bytes;
  final String sha256;

  /// Whether this surah has its own basmala recording — ayah `000`.
  ///
  /// Three states, and the third is why this is nullable. `false` is the one
  /// that earns its keep: a streamed basmala cannot be probed for existence
  /// without a request, so a manifest that declares its absence is what stops
  /// a session opening with a 404 instead of «بسم الله الرحمن الرحيم». `true`
  /// says the file is there. `null` is a manifest that does not say, and is
  /// treated optimistically — the layout in CLAUDE.md A.5 puts a basmala in
  /// every `separate` surah, so the older behaviour stands where nothing is
  /// declared.
  final bool? hasBasmala;

  /// Extra bitrates this surah is published at, keyed by bitrate.
  ///
  /// Optional and usually empty: a reciter has one bitrate, the top-level
  /// [bytes] and [sha256] describe it, and the quality selector then has
  /// nothing to choose from and says so by falling back. A CDN that publishes
  /// 32 and 128 alongside the default fills this in, and each entry carries
  /// its own digest, because a different encode is a different file.
  final Map<int, PackVariant> qualities;

  @override
  List<Object?> get props => <Object?>[
    number,
    ayahs,
    bytes,
    sha256,
    hasBasmala,
    qualities,
  ];
}

/// A reciter served from the CDN.
class ManifestReciter extends Equatable {
  const ManifestReciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.riwayah,
    required this.bitrate,
    required this.version,
    required this.audioPath,
    required this.packPath,
    required this.totalBytes,
    required this.surahs,
    this.imagePath,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String riwayah;
  final int bitrate;
  final String version;

  /// e.g. `audio/{id}/{bitrate}/{s3}{a3}.mp3`.
  final String audioPath;

  /// e.g. `packs/{id}/{bitrate}/{s3}.zip`.
  final String packPath;

  /// The reciter's portrait on the CDN, relative to the manifest's `baseUrl`
  /// — `images/<id>.jpg`.
  ///
  /// This is what lets a reciter be added without shipping an app version: a
  /// reciter who is not in `reciters.json` has no bundled portrait, and
  /// without this the app could only ever show their initial.
  final String? imagePath;
  final int totalBytes;
  final List<ManifestSurah> surahs;

  ManifestSurah? surah(int number) =>
      surahs.where((ManifestSurah s) => s.number == number).firstOrNull;

  /// The bitrates [surahNumber] is published at, the reciter's own first.
  List<int> bitratesFor(int surahNumber) {
    final ManifestSurah? entry = surah(surahNumber);
    if (entry == null) return const <int>[];
    return <int>[
      bitrate,
      ...entry.qualities.keys.where((int b) => b != bitrate),
    ];
  }

  /// The pack to fetch for [surahNumber] at [preferredBitrate].
  ///
  /// A preference this reciter does not publish falls back to their own
  /// bitrate rather than failing: the quality selector is a preference, and a
  /// reciter who only exists at 64 is still worth listening to.
  PackVariant? variantFor(int surahNumber, {int? preferredBitrate}) {
    final ManifestSurah? entry = surah(surahNumber);
    if (entry == null) return null;
    final PackVariant? preferred = preferredBitrate == null
        ? null
        : entry.qualities[preferredBitrate];
    if (preferred != null) return preferred;
    return PackVariant(
      bitrate: bitrate,
      bytes: entry.bytes,
      sha256: entry.sha256,
    );
  }

  /// The bitrate this reciter serves for [surahNumber] given a preference.
  int bitrateFor(int surahNumber, {int? preferredBitrate}) =>
      variantFor(surahNumber, preferredBitrate: preferredBitrate)?.bitrate ??
      bitrate;

  /// [audioPath] filled in for one ayah. Ayah 0 is the surah's basmala.
  String audioPathFor(int surah, int ayah, {int? bitrate}) =>
      _fill(audioPath, surah, ayah, bitrate ?? this.bitrate);

  String packPathFor(int surah, {int? bitrate}) =>
      _fill(packPath, surah, 0, bitrate ?? this.bitrate);

  String _fill(String template, int surah, int ayah, int bitrate) => template
      .replaceAll('{id}', id)
      .replaceAll('{bitrate}', '$bitrate')
      .replaceAll('{s3}', _pad3(surah))
      .replaceAll('{a3}', _pad3(ayah));

  static String _pad3(int n) => n.toString().padLeft(3, '0');

  @override
  List<Object?> get props => <Object?>[
    id,
    nameAr,
    nameEn,
    riwayah,
    bitrate,
    version,
    audioPath,
    packPath,
    imagePath,
    totalBytes,
    surahs,
  ];
}

/// The CDN's catalog of remote reciters.
class AudioManifest extends Equatable {
  const AudioManifest({
    required this.schemaVersion,
    required this.baseUrl,
    required this.mirrors,
    required this.reciters,
  });

  /// The schema this app reads. A manifest with another major version is
  /// ignored rather than half-understood.
  static const int supportedSchemaVersion = 1;

  static const AudioManifest empty = AudioManifest(
    schemaVersion: supportedSchemaVersion,
    baseUrl: '',
    mirrors: <String>[],
    reciters: <ManifestReciter>[],
  );

  final int schemaVersion;
  final String baseUrl;
  final List<String> mirrors;
  final List<ManifestReciter> reciters;

  /// [path] resolved against [baseUrl].
  ///
  /// The trailing slash is added when it is missing, because
  /// `Uri.resolve` treats the last segment of a base as a file name and would
  /// drop it: a bucket published as `…/iqra-cdn` would otherwise serve
  /// `…/audio/…` instead of `…/iqra-cdn/audio/…`. A CDN's own spelling of its
  /// base url is not something the app should be fragile about.
  Uri urlFor(String path) {
    final Uri base = Uri.parse(baseUrl);
    return (base.path.isEmpty || base.path.endsWith('/')
            ? base
            : base.replace(path: '${base.path}/'))
        .resolve(path);
  }

  /// Throws [AssetParseException] on anything that is not a well-formed
  /// manifest this app can read.
  factory AudioManifest.fromJson(Object? json, String source) {
    Never bad(String why) => throw AssetParseException(source, why);

    if (json is! Map<String, dynamic>) bad('manifest is not a JSON object');
    final Object? version = json['schemaVersion'];
    if (version is! int) bad('missing schemaVersion');
    if (version != supportedSchemaVersion) {
      bad('schemaVersion $version is not supported');
    }
    final Object? baseUrl = json['baseUrl'];
    if (baseUrl is! String) bad('missing baseUrl');

    String str(Map<String, dynamic> m, String key) => switch (m[key]) {
      final String v when v.isNotEmpty => v,
      _ => bad('reciter is missing "$key"'),
    };
    int integer(Map<String, dynamic> m, String key) => switch (m[key]) {
      final int v => v,
      _ => bad('"$key" is not an integer'),
    };

    final List<ManifestReciter> reciters = <ManifestReciter>[
      for (final Object? r
          in (json['reciters'] as List<dynamic>? ?? <dynamic>[]))
        if (r is Map<String, dynamic>)
          ManifestReciter(
            id: str(r, 'id'),
            nameAr: str(r, 'nameAr'),
            nameEn: str(r, 'nameEn'),
            riwayah: r['riwayah'] as String? ?? '',
            bitrate: integer(r, 'bitrate'),
            version: '${r['version'] ?? ''}',
            audioPath: str(r, 'audioPath'),
            packPath: str(r, 'packPath'),
            imagePath: switch (r['imagePath']) {
              final String path when path.isNotEmpty => path,
              _ => null,
            },
            totalBytes: r['totalBytes'] as int? ?? 0,
            surahs: <ManifestSurah>[
              for (final Object? s
                  in (r['surahs'] as List<dynamic>? ?? <dynamic>[]))
                if (s is Map<String, dynamic>)
                  ManifestSurah(
                    number: integer(s, 'n'),
                    ayahs: integer(s, 'ayahs'),
                    bytes: s['bytes'] as int? ?? 0,
                    sha256: s['sha256'] as String? ?? '',
                    hasBasmala: s['hasBasmala'] as bool?,
                    qualities: _qualities(s['qualities']),
                  ),
            ],
          )
        else
          bad('reciter entry is not an object'),
    ];

    return AudioManifest(
      schemaVersion: version,
      baseUrl: baseUrl,
      mirrors: <String>[
        for (final Object? m
            in (json['mirrors'] as List<dynamic>? ?? <dynamic>[]))
          if (m is String) m,
      ],
      reciters: reciters,
    );
  }

  /// `{"32": {"bytes": …, "sha256": …}}`, skipping anything malformed.
  ///
  /// Skipping rather than throwing: an unreadable extra quality costs the
  /// selector one option, where refusing the manifest would cost the reciter
  /// entirely.
  static Map<int, PackVariant> _qualities(Object? raw) {
    if (raw is! Map) return const <int, PackVariant>{};
    final Map<int, PackVariant> out = <int, PackVariant>{};
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      final int? bitrate = int.tryParse('${entry.key}');
      final Object? value = entry.value;
      if (bitrate == null || bitrate <= 0 || value is! Map) continue;
      final Object? bytes = value['bytes'];
      final Object? digest = value['sha256'];
      if (bytes is! int) continue;
      out[bitrate] = PackVariant(
        bitrate: bitrate,
        bytes: bytes,
        sha256: digest is String ? digest : '',
      );
    }
    return Map<int, PackVariant>.unmodifiable(out);
  }

  @override
  List<Object?> get props => <Object?>[
    schemaVersion,
    baseUrl,
    mirrors,
    reciters,
  ];
}
