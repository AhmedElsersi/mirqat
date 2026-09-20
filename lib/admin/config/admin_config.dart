/// Credentials and settings for the admin tool, from `--dart-define`.
///
/// Nothing here has a fallback, and nothing here is ever written down: the
/// values come from `admin.env` through `run_admin.sh`, which is gitignored.
/// A build that forgets one is refused at launch with the names of what is
/// missing, because the alternative — a tool that starts and fails halfway
/// through an upload — is worse than not starting.
class AdminConfig {
  const AdminConfig({
    required this.accountId,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    required this.endpoint,
    required this.publicBase,
    required this.bitrate,
    this.githubToken = '',
    this.githubRepo = '',
    this.manifestPath = 'manifest.json',
    this.appInfoPath = 'app.json',
    this.projectDir = '',
  });

  /// Reads the compile-time environment. Every field is required; see
  /// [missingKeys] for what a caller should check first.
  factory AdminConfig.fromEnvironment() => AdminConfig(
    accountId: _accountId,
    accessKey: _accessKey,
    secretKey: _secretKey,
    bucket: _bucket,
    endpoint: _endpoint,
    publicBase: _publicBase,
    bitrate: int.tryParse(_bitrate) ?? 0,
    githubToken: _githubToken,
    githubRepo: _githubRepo,
    manifestPath: _manifestPath.isEmpty ? 'manifest.json' : _manifestPath,
    appInfoPath: _appInfoPath.isEmpty ? 'app.json' : _appInfoPath,
    projectDir: _projectDir,
  );

  final String accountId;

  /// Never logged, never rendered, never written to disk by this app.
  final String accessKey;
  final String secretKey;
  final String bucket;

  /// The S3 API endpoint — `https://<account>.r2.cloudflarestorage.com`.
  final String endpoint;

  /// The public read base that goes into the manifest as `baseUrl`.
  final String publicBase;

  /// The bitrate segments are encoded at, and the `{bitrate}` path segment.
  final int bitrate;

  /// A GitHub token with write access to the Pages repo, and the repo itself
  /// as `owner/name`.
  ///
  /// **Optional**, and the only optional credential here. Without it the tool
  /// writes the manifest to disk and says so, which is what it always did.
  /// With it, adding a reciter or a surah needs nothing else: the manifest the
  /// app reads is published in the same step, and no app release is involved.
  final String githubToken;
  final String githubRepo;

  /// Where the manifest lives inside that repo.
  final String manifestPath;

  /// Where `app.json` lives inside that repo — beside the manifest, which is
  /// where the app looks for it.
  final String appInfoPath;

  /// The checkout the tool was started from, so that what it publishes can
  /// also be written into the app's own bundled copies. Not a credential, and
  /// optional: without it the tool says what to copy where.
  final String projectDir;

  /// Whether the manifest can be published from here.
  bool get canPublishManifest =>
      githubToken.isNotEmpty && githubRepo.contains('/');

  static const String _accountId = String.fromEnvironment('R2_ACCOUNT_ID');
  static const String _accessKey = String.fromEnvironment('R2_ACCESS_KEY');
  static const String _secretKey = String.fromEnvironment('R2_SECRET_KEY');
  static const String _bucket = String.fromEnvironment('R2_BUCKET');
  static const String _endpoint = String.fromEnvironment('R2_ENDPOINT');
  static const String _publicBase = String.fromEnvironment('R2_PUBLIC_BASE');
  static const String _bitrate = String.fromEnvironment('AUDIO_BITRATE');
  static const String _githubToken = String.fromEnvironment('GITHUB_TOKEN');
  static const String _githubRepo = String.fromEnvironment('GITHUB_REPO');
  static const String _manifestPath = String.fromEnvironment(
    'GITHUB_MANIFEST_PATH',
  );
  static const String _appInfoPath = String.fromEnvironment(
    'GITHUB_APP_INFO_PATH',
  );
  static const String _projectDir = String.fromEnvironment('PROJECT_DIR');

  /// The `--dart-define` names that were not supplied, in the order
  /// `admin.env` lists them. Empty means the tool can start.
  static List<String> get missingKeys => <String>[
    if (_accountId.isEmpty) 'R2_ACCOUNT_ID',
    if (_accessKey.isEmpty) 'R2_ACCESS_KEY',
    if (_secretKey.isEmpty) 'R2_SECRET_KEY',
    if (_bucket.isEmpty) 'R2_BUCKET',
    if (_endpoint.isEmpty) 'R2_ENDPOINT',
    if (_publicBase.isEmpty) 'R2_PUBLIC_BASE',
    if (int.tryParse(_bitrate) == null || int.parse(_bitrate) <= 0)
      'AUDIO_BITRATE',
  ];

  /// What to show the operator when [missingKeys] is not empty.
  ///
  /// Names the keys and how to supply them; never guesses a value and never
  /// suggests a default, because a wrong bucket is an upload into someone
  /// else's namespace.
  static String missingMessage(List<String> keys) =>
      'The admin tool cannot start: '
      '${keys.join(', ')} ${keys.length == 1 ? 'is' : 'are'} missing.\n\n'
      'These come from admin.env through run_admin.sh:\n'
      '    ./run_admin.sh\n\n'
      'admin.env is gitignored and holds live Cloudflare R2 credentials. '
      'Copy admin.dev.example to admin.env and fill it in; never commit it, '
      'and never add a fallback in code.';

  /// The object key for one ayah, matching the manifest's `audioPath`
  /// template (CLAUDE.md A.5).
  String audioKey({
    required String reciterId,
    required int surah,
    required int ayah,
  }) => 'audio/$reciterId/$bitrate/${_pad3(surah)}${_pad3(ayah)}.mp3';

  /// The object key for one surah's pack.
  String packKey({required String reciterId, required int surah}) =>
      'packs/$reciterId/$bitrate/${_pad3(surah)}.zip';

  /// Where an uploaded object can be read back from.
  Uri publicUrlFor(String key) {
    final String base = publicBase.endsWith('/') ? publicBase : '$publicBase/';
    return Uri.parse(base).resolve(key);
  }

  static String _pad3(int n) => n.toString().padLeft(3, '0');
}
