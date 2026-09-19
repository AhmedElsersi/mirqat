/// Where the CDN publishes the audio manifest.
///
/// A constant of its own, deliberately free of any Flutter import: the app,
/// the admin tool and plain `dart run` scripts all need it, and making them
/// reach into `ManifestService` for it drags `path_provider` — a plugin — into
/// programs that have no Flutter engine to talk to.
///
/// The manifest lives on a GitHub Pages site holding nothing else; the audio
/// itself lives wherever the manifest's own `baseUrl` points. That indirection
/// is what lets the bucket move without an app update (CLAUDE.md A.5).
///
/// Overridable at build time with `--dart-define=MANIFEST_URL=…`, which is how
/// a staging manifest is tried without touching this constant.
const String kManifestUrl = String.fromEnvironment(
  'MANIFEST_URL',
  defaultValue: 'https://ahmedelsersi.github.io/iqra-cdn/manifest.json',
);
