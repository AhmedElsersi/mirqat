import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/theme/app_colors.dart';

/// WCAG 2.1 relative luminance (§ definition of "relative luminance").
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio: (lighter + 0.05) / (darker + 0.05).
double contrastRatio(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('WCAG contrast — the four mode-specific pairings', () {
    // These are the tokens that were split per mode precisely because a single
    // value failed. If one of them drops below 4.5 the split has been undone.
    const Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
      'mutedLight on vellum': (AppColors.mutedLight, AppColors.vellum),
      'sabrLight on vellum': (AppColors.sabrLight, AppColors.vellum),
      'mutedDark on inkDeep': (AppColors.mutedDark, AppColors.inkDeep),
      'sabrDark on inkDeep': (AppColors.sabrDark, AppColors.inkDeep),
    };

    pairs.forEach((String name, (Color, Color) pair) {
      test('$name clears AA body text (4.5:1)', () {
        expect(contrastRatio(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      });
    });
  });

  group('WCAG contrast — primary text', () {
    test('ink on vellum', () {
      expect(
        contrastRatio(AppColors.ink, AppColors.vellum),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('vellum on inkDeep', () {
      expect(
        contrastRatio(AppColors.vellum, AppColors.inkDeep),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('secondary text clears 4.5 on the surface it actually sits on', () {
      expect(
        contrastRatio(AppColors.lightTextSecondary, AppColors.lightSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(AppColors.darkTextSecondary, AppColors.darkSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(AppColors.darkTextSecondary, AppColors.darkBackground),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('error is readable in the mode that uses it', () {
      expect(
        contrastRatio(AppColors.error, AppColors.lightBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(AppColors.errorDark, AppColors.darkSurface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('WCAG contrast — non-text UI components (3:1)', () {
    test('mode-blind status colours clear 3:1 in both modes', () {
      for (final Color status in <Color>[
        AppColors.statusNotStarted,
        AppColors.statusMemorized,
      ]) {
        expect(
          contrastRatio(status, AppColors.vellum),
          greaterThanOrEqualTo(3.0),
        );
        expect(
          contrastRatio(status, AppColors.inkDeep),
          greaterThanOrEqualTo(3.0),
        );
      }
    });
  });

  test('gold is never legible as text on vellum — the rule has a number', () {
    // Guards the hard rule rather than a preference: if someone "fixes" gold
    // so this passes, they have changed the brand colour, and this test tells
    // them so instead of letting it through silently.
    expect(contrastRatio(AppColors.gold, AppColors.vellum), lessThan(3.0));
    expect(
      contrastRatio(AppColors.gold, AppColors.inkDeep),
      greaterThanOrEqualTo(4.5),
    );
  });
}
