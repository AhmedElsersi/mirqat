// Uploads the packed QPC V2 page fonts to R2, where the app fetches them.
//
// Reads what tool/build_qpc_fonts.py wrote: the packed fonts in DIR, and
// assets/data/qpc_v2_fonts.json, which names each one's path, size and
// digest. Every file is checked against that list before it is sent, so what
// goes up is exactly what the app will accept. A path already holding the
// same bytes is left alone; one holding different bytes is refused, as audio
// is (R2Client) — a font is replaced by publishing it under a new path.
//
//   dart run tool/publish_fonts.dart --dry-run build/qpc_v2
//   dart run tool/publish_fonts.dart build/qpc_v2
//
// Credentials come from admin.env, as tool/publish_surah.dart reads them.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final bool dryRun = args.contains('--dry-run');
  final List<String> rest = <String>[
    for (final String a in args)
      if (!a.startsWith('--')) a,
  ];
  if (rest.length != 1) {
    stderr.writeln('usage: dart run tool/publish_fonts.dart [--dry-run] DIR');
    exit(64);
  }
  final String dir = rest.single;
  final Map<String, dynamic> list =
      jsonDecode(File('assets/data/qpc_v2_fonts.json').readAsStringSync())
          as Map<String, dynamic>;
  final String template = list['path'] as String;
  final List<dynamic> pages = list['pages'] as List<dynamic>;

  // Every file checked first: a mismatch stops the run before anything is
  // sent, rather than leaving half a set published.
  final List<({String key, File file})> uploads = <({String key, File file})>[];
  for (final dynamic raw in pages) {
    final Map<String, dynamic> page = raw as Map<String, dynamic>;
    final int n = page['n'] as int;
    final String n3 = n.toString().padLeft(3, '0');
    final File file = File(p.join(dir, 'p$n3.ttf.gz'));
    if (!file.existsSync()) _fail('${file.path} is missing');
    final List<int> bytes = file.readAsBytesSync();
    if (bytes.length != page['bytes'] ||
        sha256.convert(bytes).toString() != page['sha256']) {
      _fail('${file.path} does not match qpc_v2_fonts.json — rebuild both');
    }
    uploads.add((key: template.replaceAll('{n3}', n3), file: file));
  }
  stdout.writeln('${uploads.length} fonts checked against the list.');
  if (dryRun) {
    stdout.writeln('Dry run: nothing uploaded. First key: ${uploads.first.key}');
    return;
  }

  final R2Client r2 = R2Client(adminConfig: _config());
  int uploaded = 0;
  int unchanged = 0;
  for (final ({String key, File file}) u in uploads) {
    final UploadResult result = await r2.putFile(
      key: u.key,
      file: u.file,
      contentType: 'application/gzip',
    );
    if (result.outcome == UploadOutcome.unchanged) {
      unchanged++;
    } else {
      uploaded++;
    }
    stdout.write('\r${uploaded + unchanged}/${uploads.length}');
  }
  stdout.writeln('\nUploaded $uploaded, already there $unchanged.');
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(1);
}

AdminConfig _config() {
  final Map<String, String> env = <String, String>{};
  for (final String line in File('admin.env').readAsLinesSync()) {
    final String t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final int i = t.indexOf('=');
    env[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return AdminConfig(
    accountId: env['R2_ACCOUNT_ID']!,
    accessKey: env['R2_ACCESS_KEY']!,
    secretKey: env['R2_SECRET_KEY']!,
    bucket: env['R2_BUCKET']!,
    endpoint: env['R2_ENDPOINT']!,
    publicBase: env['R2_PUBLIC_BASE']!,
    bitrate: int.parse(env['AUDIO_BITRATE']!),
  );
}
