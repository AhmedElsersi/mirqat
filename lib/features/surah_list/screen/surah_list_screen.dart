import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/localization/locale_keys.dart';

/// Home screen. Phase 0 renders the bare shell; the catalog-backed list
/// arrives in Phase 4.
class SurahListScreen extends StatelessWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.surahListTitle.tr())),
      body: const SizedBox.shrink(),
    );
  }
}
