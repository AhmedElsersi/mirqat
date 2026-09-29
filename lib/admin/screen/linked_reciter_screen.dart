import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/linked_reciter_cubit.dart';

/// Adds a reciter from a file of links: choose the file, say who the reciter
/// is, ask the host what it holds, publish.
///
/// A workbench form like the rest of the tool: English labels, one scrolling
/// page, the problems and the publish button pinned at the foot.
class LinkedReciterScreen extends StatelessWidget {
  const LinkedReciterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<LinkedReciterCubit, LinkedReciterState>(
        builder: (BuildContext context, LinkedReciterState state) {
          final LinkedReciterCubit cubit = context.read<LinkedReciterCubit>();
          return Scaffold(
            appBar: AppBar(
              title: const Text('Mirqat — reciter from a file of links'),
              bottom: state.busy || state.probing
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(4),
                      child: LinearProgressIndicator(
                        value: state.probing ? state.probeProgress : null,
                      ),
                    )
                  : null,
              actions: <Widget>[
                TextButton.icon(
                  onPressed: state.loading ? null : cubit.load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload the live manifest'),
                ),
                TextButton.icon(
                  onPressed: state.row == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: cubit.json));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Entry copied.')),
                          );
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy entry'),
                ),
              ],
            ),
            body: state.loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: <Widget>[
                      Expanded(
                        child: _Form(state: state, cubit: cubit),
                      ),
                      const Divider(height: 1),
                      _Footer(state: state, cubit: cubit),
                    ],
                  ),
          );
        },
      );
}

class _Form extends StatelessWidget {
  const _Form({required this.state, required this.cubit});

  final LinkedReciterState state;
  final LinkedReciterCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final LinkedReciterDraft d = state.draft;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            state.manifestLive
                ? 'The entry is merged into the manifest as it is live now.'
                : 'The live manifest could not be read: the entry would go '
                      'into a manifest built from nothing. Reload before '
                      'publishing.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _Section(
            title: '1. The file of links',
            children: <Widget>[
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: state.busy || state.probing
                        ? null
                        : cubit.chooseFile,
                    icon: const Icon(Icons.description_outlined),
                    label: Text(
                      state.file == null ? 'Choose file…' : 'Change file…',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      state.filePath ??
                          'A QUL recitation export: one audio '
                              'address per ayah.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (state.file case final file?) ...<Widget>[
                const SizedBox(height: 8),
                SelectableText(
                  '${file.ayahCount} ayahs across ${file.surahs.length} '
                  'surah(s), every one at\n${file.template}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          _Section(
            title: '2. The reciter',
            children: <Widget>[
              _Field(
                label: 'id (lower-case, digits, underscores)',
                value: d.id,
                onChanged: (String v) => cubit.edit(
                  (LinkedReciterDraft x) => x.copyWith(id: v.trim()),
                ),
              ),
              // Keyed by the id: an id that names a reciter already in the
              // manifest fills these in, and the fields have to show it.
              KeyedSubtree(
                key: ValueKey<String>('names-${d.id}'),
                child: Column(
                  children: <Widget>[
                    _Field(
                      label: 'Name (Arabic)',
                      value: d.nameAr,
                      rtl: true,
                      onChanged: (String v) => cubit.edit(
                        (LinkedReciterDraft x) => x.copyWith(nameAr: v),
                      ),
                    ),
                    _Field(
                      label: 'Name (English)',
                      value: d.nameEn,
                      onChanged: (String v) => cubit.edit(
                        (LinkedReciterDraft x) => x.copyWith(nameEn: v),
                      ),
                    ),
                    _Field(
                      label: 'Riwayah (Arabic, e.g. حفص عن عاصم)',
                      value: d.riwayah,
                      rtl: true,
                      onChanged: (String v) => cubit.edit(
                        (LinkedReciterDraft x) => x.copyWith(riwayah: v),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _Field(
                            label: 'Version (bump it when the host re-cuts)',
                            value: d.version,
                            onChanged: (String v) => cubit.edit(
                              (LinkedReciterDraft x) =>
                                  x.copyWith(version: v.trim()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey<int?>(state.measuredBitrate),
                            child: _Field(
                              label: state.measuredBitrate == null
                                  ? 'Bitrate, kbps (the probe measures it)'
                                  : 'Bitrate, kbps (measured '
                                        '${state.measuredBitrate})',
                              value: d.bitrate?.toString() ?? '',
                              onChanged: (String v) => cubit.edit(
                                (LinkedReciterDraft x) =>
                                    x.copyWith(bitrate: int.tryParse(v)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: state.busy ? null : cubit.choosePortrait,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      d.imagePath == null ? 'Portrait…' : 'Change portrait…',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d.imagePath ?? 'No portrait: the app shows the initial.',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (d.imagePath != null)
                    TextButton(
                      onPressed: cubit.removePortrait,
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
          _Section(
            title: '3. The host',
            children: <Widget>[
              Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: state.file == null || state.probing || state.busy
                        ? null
                        : cubit.probe,
                    icon: const Icon(Icons.travel_explore_outlined),
                    label: Text(state.probed ? 'Probe again' : 'Probe host'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Asks for the first ayah of every complete surah, and '
                      'for the basmala (000) of every surah that has one of '
                      'its own — the manifest has to say whether it exists.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              if (state.plan.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                _PlanTable(plan: state.plan),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanTable extends StatelessWidget {
  const _PlanTable({required this.plan});

  final List<SurahPlan> plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? small = theme.textTheme.bodySmall;
    return Table(
      columnWidths: const <int, TableColumnWidth>{
        0: FixedColumnWidth(48),
        1: FixedColumnWidth(140),
        2: FixedColumnWidth(90),
        3: FixedColumnWidth(90),
        4: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          children: <Widget>[
            for (final String h in <String>[
              '#',
              'Surah',
              'Ayahs',
              'Basmala',
              'Status',
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  h,
                  style: small?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        for (final SurahPlan s in plan)
          TableRow(
            decoration: BoxDecoration(
              color: s.publishable
                  ? null
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
            ),
            children: <Widget>[
              Text('${s.number}', style: small),
              Text(s.nameAr, style: small, textDirection: TextDirection.rtl),
              Text(
                s.inFile
                    ? '${s.listed.where((int a) => a > 0).length} / '
                          '${s.ayahCount}'
                    : '— / ${s.ayahCount}',
                style: small,
              ),
              Text(_basmala(s), style: small),
              Text(
                _status(s),
                style: small?.copyWith(
                  color:
                      s.inFile &&
                          !s.publishable &&
                          s.probe != ProbeOutcome.untried
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
      ],
    );
  }

  static String _basmala(SurahPlan s) {
    if (!s.separate) return 'in ayah 1 / none';
    return switch (s.basmala) {
      null => '?',
      true => 'on host (000)',
      false => 'none on host',
    };
  }

  static String _status(SurahPlan s) {
    if (!s.inFile) return 'not in the file';
    if (!s.complete) {
      return <String>[
        if (s.missing.isNotEmpty) 'missing ${s.missing.take(6).join(', ')}',
        if (s.extra.isNotEmpty) 'extra ${s.extra.take(6).join(', ')}',
      ].join('; ');
    }
    return switch (s.probe) {
      ProbeOutcome.untried => 'complete — not probed yet',
      ProbeOutcome.ok => 'will be offered',
      ProbeOutcome.notFound => 'not on the host (404)',
      ProbeOutcome.error => 'the host did not answer',
    };
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.cubit});

  final LinkedReciterState state;
  final LinkedReciterCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> problems = state.problems;
    final List<String> warnings = state.warnings;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final String problem in problems)
            Text(
              '• $problem',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          for (final String warning in warnings)
            Text('• $warning', style: theme.textTheme.bodySmall),
          if (state.error case final String error)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (state.message case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(message, style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              FilledButton.icon(
                onPressed: problems.isEmpty && !state.busy && !state.probing
                    ? cubit.publish
                    : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  state.publishable.isEmpty
                      ? 'Publish'
                      : 'Publish ${state.publishable.length} surah(s)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.rtl = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool rtl;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: value,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    ),
  );
}
