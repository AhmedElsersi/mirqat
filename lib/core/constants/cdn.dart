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

/// Where the CDN publishes `app.json`: what the app says about itself, and
/// which versions of it are still welcome. Beside the manifest, on the same
/// Pages site, and fetched the same way — a public GET that fails quietly to
/// the copy on the device (CLAUDE.md A.2 rule 3, A.5).
///
/// Overridable at build time with `--dart-define=APP_INFO_URL=…`.
const String kAppInfoUrl = String.fromEnvironment(
  'APP_INFO_URL',
  defaultValue: 'https://ahmedelsersi.github.io/iqra-cdn/app.json',
);
