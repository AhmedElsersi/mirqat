import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The admin tool must never reach a phone.
///
/// It holds R2 credentials, shells out to ffmpeg, and can write to a public
/// bucket. None of that belongs in an app people install, and the only thing
/// keeping it out is that `lib/main.dart` cannot reach `lib/admin/` through
/// any chain of imports. This walks that chain for real rather than trusting
/// the directory layout.
void main() {
  final Directory lib = Directory('lib');

  /// Every relative import in [file], resolved to a path under `lib/`.
  Set<String> importsOf(File file) {
    final RegExp importLine = RegExp(
      '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final Set<String> out = <String>{};
    for (final RegExpMatch match in importLine.allMatches(
      file.readAsStringSync(),
    )) {
      final String target = match.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:flutter')) {
        continue;
      }
      if (target.startsWith('package:mirqat/')) {
        out.add(p.join('lib', target.substring('package:mirqat/'.length)));
        continue;
      }
      if (target.startsWith('package:')) continue;
      out.add(p.normalize(p.join(p.dirname(file.path), target)));
    }
    return out;
  }

  /// Everything reachable from [entry], transitively.
  Set<String> reachableFrom(String entry) {
    final Set<String> seen = <String>{};
    final List<String> queue = <String>[entry];
    while (queue.isNotEmpty) {
      final String path = queue.removeLast();
      if (!seen.add(path)) continue;
      final File file = File(path);
      if (!file.existsSync()) continue;
      queue.addAll(importsOf(file));
    }
    return seen;
  }

  test('lib/main.dart cannot reach anything under lib/admin/', () {
    final Set<String> reachable = reachableFrom('lib/main.dart');

    final List<String> admin = reachable
        .where((String path) => p.split(path).contains('admin'))
        .toList();

    expect(
      admin,
      isEmpty,
      reason:
          'The app entry point can reach the admin tool through: '
          '${admin.join(', ')}. That would ship R2 credentials and an '
          'ffmpeg pipeline to a phone.',
    );
  });

  test('the admin entry point exists and is the only way into lib/admin/', () {
    expect(File('lib/main_admin.dart').existsSync(), isTrue);

    final Set<String> reachable = reachableFrom('lib/main_admin.dart');
    expect(
      reachable.where((String path) => p.split(path).contains('admin')),
      isNotEmpty,
      reason: 'the admin entry point should reach the admin tool',
    );
  });

  test('nothing outside lib/admin/ imports lib/admin/', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (p.split(entity.path).contains('admin')) continue;
      if (p.basename(entity.path) == 'main_admin.dart') continue;

      if (importsOf(entity).any((String i) => p.split(i).contains('admin'))) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('no credential is written down anywhere in lib/', () {
    // The keys are read from --dart-define and nothing else. A literal that
    // looks like a secret in source is how one ends up in a committed build.
    final RegExp suspicious = RegExp(
      r'''(R2_(?:ACCESS|SECRET)_KEY|r2\.cloudflarestorage\.com)\s*[:=]\s*['"][^'"]+['"]''',
    );
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (suspicious.hasMatch(entity.readAsStringSync())) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('admin.env is ignored by git, so credentials cannot be committed', () {
    final ProcessResult result = Process.runSync('git', <String>[
      'check-ignore',
      'admin.env',
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'admin.env holds live R2 keys and must stay out of git',
    );

    final ProcessResult tracked = Process.runSync('git', <String>[
      'ls-files',
      '--error-unmatch',
      'admin.env',
    ]);
    expect(
      tracked.exitCode,
      isNot(0),
      reason:
          'admin.env must not be tracked; unstage it with '
          '`git rm --cached admin.env`',
    );
  });
}
