import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../core/state/load_status.dart';
import '../../core/widgets/ayah_text.dart';
import '../../data/models/ayah.dart';
import '../../data/models/surah.dart';
import '../cubit/admin_cubit.dart';
import '../cubit/admin_state.dart';
import 'admin_text_scale.dart';
import '../services/batch_split.dart';
import '../services/publish_guard.dart';
import '../services/segment_planner.dart';
import '../services/timecode.dart';

/// The whole tool: pick a recording and a surah, split it, review every
/// segment against its ayah, publish.
///
/// Deliberately plain. This is an internal Mac tool for one operator, and
/// every minute spent styling it is a minute not spent on the app people
/// actually use.
class AdminScreen extends StatelessWidget {
  const AdminScreen({this.appInfoEditor, this.linkedReciter, super.key});

  /// Builds the `app.json` editor, with whatever it needs already provided.
  /// Handed in rather than built here, because what it needs — the Pages
  /// publisher, the R2 client — is made where the credentials are, in
  /// `main_admin.dart`. Null leaves the button out.
  final WidgetBuilder? appInfoEditor;

  /// Builds the "reciter from a file of links" screen, likewise. Null leaves
  /// the button out.
  final WidgetBuilder? linkedReciter;

  @override
  Widget build(BuildContext context) => BlocBuilder<AdminCubit, AdminState>(
    builder: (BuildContext context, AdminState state) {
      final AdminCubit cubit = context.read<AdminCubit>();

      return Scaffold(
        appBar: AppBar(
          title: const Text('Mirqat — audio admin'),
          actions: <Widget>[
            const _TextSizeControls(),
            if (linkedReciter != null)
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: linkedReciter!)),
                icon: const Icon(Icons.link),
                label: const Text('Reciter from a file of links'),
              ),
            if (appInfoEditor != null)
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: appInfoEditor!)),
                icon: const Icon(Icons.info_outline),
                label: const Text('app.json — about, developer, updates'),
              ),
            const SizedBox(width: 8),
          ],
          // Export and upload have a fraction; a split or a running batch
          // only has "still working", which is still worth showing — a
          // two-hour surah splits for a while, and a dead-looking tool gets
          // its window shaken.
          bottom:
              state.progress == null &&
                  state.stage != AdminStage.splitting &&
                  !state.batchRunning
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: state.progress),
                ),
        ),
        body: switch (state.status) {
          LoadStatus.initial || LoadStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          LoadStatus.failure => _Fatal(message: state.errorMessage ?? ''),
          LoadStatus.ready => _Workspace(state: state, cubit: cubit),
        },
      );
    },
  );
}

/// The text-size buttons: the same three moves as ⌘− ⌘0 ⌘+, for a hand
/// already on the mouse. The percentage shows only once the size has been
/// moved, and tapping it puts the size back. Built without the scope — a
/// bare screen in a test — there is nothing to control, so nothing shows.
class _TextSizeControls extends StatelessWidget {
  const _TextSizeControls();

  @override
  Widget build(BuildContext context) {
    final AdminTextScale? size = AdminTextScale.of(context);
    if (size == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: 'Smaller text (⌘−)',
          onPressed: size.canDecrease ? size.decrease : null,
          icon: const Icon(Icons.text_decrease),
        ),
        if (!size.isDefault)
          Tooltip(
            message: 'Back to the normal size (⌘0)',
            child: TextButton(
              onPressed: size.reset,
              child: Text('${size.percent}%'),
            ),
          ),
        IconButton(
          tooltip: 'Larger text (⌘+)',
          onPressed: size.canIncrease ? size.increase : null,
          icon: const Icon(Icons.text_increase),
        ),
      ],
    );
  }
}

/// A stop rather than a screen: no ffmpeg, no catalog, nothing to do.
class _Fatal extends StatelessWidget {
  const _Fatal({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: SelectableText(
        message,
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    // The controls at the top are a Wrap: narrow the window and they take
    // more rows, and in a short window they used to push the review list to
    // nothing — a tool with no list in it, and an overflow stripe where the
    // clips should be. They are held to a little over half the height and
    // scroll inside that, so the list is always there to work in.
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints space) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: space.maxHeight * 0.55),
            child: SingleChildScrollView(
              child: _Head(state: state, cubit: cubit),
            ),
          ),
          const Divider(),
          if (state.plan != null) _ReviewBar(state: state, cubit: cubit),
          Expanded(
            child: _Review(state: state, cubit: cubit),
          ),
          if (state.log.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView(
                reverse: true,
                children: <Widget>[
                  for (final String line in state.log.reversed)
                    SelectableText(line, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Everything above the review list: what to cut, what came of it, and the
/// way past the guard.
class _Head extends StatelessWidget {
  const _Head({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _Setup(state: state, cubit: cubit),
      if (state.batch.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        _BatchPanel(state: state, cubit: cubit),
      ],
      const SizedBox(height: 12),
      if (state.errorMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SelectableText(
            state.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      _Verdict(state: state, cubit: cubit),
      if (state.stage == AdminStage.published)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            // The step people forget, and the reason a surah can sit in the
            // bucket while the app swears it does not exist.
            child: const SelectableText(
              'Uploaded. The app still cannot see this surah until '
              'manifest.json is published to the Pages site — the path is in '
              'the log below. Copy the same file into '
              'assets/data/manifest.json so a fresh install has it too.',
            ),
          ),
        ),
    ],
  );
}

class _Setup extends StatelessWidget {
  const _Setup({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  /// A quiet caption over each group of controls, so the eye can find "the
  /// splitting knobs" without reading every label.
  Widget _groupLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 4, bottom: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _groupLabel(context, 'WHO AND WHAT'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          // A dropdown, not a text field: publishing a surah means choosing a
          // reciter who already exists, and a mistyped id would silently create a
          // second reciter nobody meant to add.
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              // Only a value the list actually holds: an id with no item — a
              // reciter added while the published manifest has not caught up —
              // trips an assertion inside DropdownButton and takes the screen
              // with it.
              initialValue:
                  state.reciters.any(
                    (AdminReciter r) => r.id == state.reciterId,
                  )
                  ? state.reciterId
                  : null,
              decoration: const InputDecoration(labelText: 'Reciter'),
              items: <DropdownMenuItem<String>>[
                for (final AdminReciter reciter in state.reciters)
                  DropdownMenuItem<String>(
                    value: reciter.id,
                    child: Text(reciter.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (String? id) =>
                  id == null ? null : cubit.setReciterId(id),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _AddReciterDialog.show(context, cubit),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add reciter…'),
          ),
          SizedBox(
            width: 260,
            // The catalog, straight out of quran.db: name and number, 114 rows,
            // nothing hardcoded here.
            child: DropdownButtonFormField<Surah>(
              isExpanded: true,
              initialValue: state.surah,
              decoration: const InputDecoration(labelText: 'Surah'),
              items: <DropdownMenuItem<Surah>>[
                for (final Surah surah in state.surahs)
                  DropdownMenuItem<Surah>(
                    value: surah,
                    child: Text('${surah.number} · ${surah.nameAr}'),
                  ),
              ],
              onChanged: (Surah? surah) =>
                  surah == null ? null : cubit.selectSurah(surah),
            ),
          ),
          _SourcePicker(state: state, cubit: cubit),
        ],
      ),
      _groupLabel(
        context,
        'WHAT THIS RECORDING HOLDS — applies to a folder too',
      ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          // What this particular recording holds besides the ayahs. The surah
          // says whether a basmala *belongs* before ayah 1; only the operator
          // knows whether the reciter's file actually has it, or opens with the
          // isti'adhah. Both change how many segments to expect.
          SizedBox(
            width: 230,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Audio has basmala'),
              subtitle: Text(
                state.surah?.bismillahMode == BismillahMode.separatePreamble
                    ? 'Untick if it starts at ayah 1'
                    : 'Not separate in this surah',
              ),
              value:
                  state.surah?.bismillahMode ==
                      BismillahMode.separatePreamble &&
                  state.recordingHasBasmala,
              // Only a surah whose basmala is its own segment has one to remove.
              onChanged:
                  state.surah?.bismillahMode == BismillahMode.separatePreamble
                  ? (bool? value) => cubit.setRecordingHasBasmala(value ?? true)
                  : null,
            ),
          ),
          SizedBox(
            width: 230,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Audio has isti'adhah"),
              subtitle: const Text('Cut off, never published'),
              value: state.recordingHasIstiadhah,
              onChanged: (bool? value) =>
                  cubit.setRecordingHasIstiadhah(value ?? false),
            ),
          ),
        ],
      ),
      _groupLabel(context, 'SPLITTING'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          // The two knobs that decide where the breaks are. Exposed because
          // reciters differ: a slow, breathy reading needs a longer minimum than
          // one that runs ayahs together, and the defaults will not suit both.
          SizedBox(
            width: 150,
            child: TextFormField(
              initialValue: '${state.thresholdDb.round()}',
              decoration: const InputDecoration(
                labelText: 'Silence threshold',
                suffixText: 'dBFS',
                helperText: 'Lower = stricter',
              ),
              keyboardType: TextInputType.number,
              onChanged: (String value) {
                final double? parsed = double.tryParse(value);
                if (parsed != null) cubit.setThresholdDb(parsed);
              },
            ),
          ),
          SizedBox(
            width: 150,
            child: TextFormField(
              initialValue: '${state.minimumSilenceMs}',
              decoration: const InputDecoration(
                labelText: 'Minimum silence',
                suffixText: 'ms',
                helperText: 'Shorter = more breaks',
              ),
              keyboardType: TextInputType.number,
              onChanged: (String value) {
                final int? parsed = int.tryParse(value);
                if (parsed != null) cubit.setMinimumSilenceMs(parsed);
              },
            ),
          ),
          FilledButton(
            onPressed: state.canSplit && state.stage != AdminStage.splitting
                ? cubit.split
                : null,
            child: Text(state.plan == null ? 'Split' : 'Split again'),
          ),
          // For a surah long enough that no threshold gives the right count.
          // Al-Baqarah yields 387 segments at one setting and 206 at the next;
          // this keeps the pauses as candidates and lets the text choose between
          // them.
          OutlinedButton.icon(
            onPressed: state.plan == null ? null : cubit.alignToText,
            icon: const Icon(Icons.straighten),
            label: const Text('Align to text'),
          ),
          // A whole folder, one recording per surah, split one after another
          // with the settings above. Nothing uploads: what needs attention goes
          // into the folder's README.md, and publishing waits for the operator.
          OutlinedButton.icon(
            onPressed: state.batchRunning ? null : cubit.chooseBatchFolder,
            icon: const Icon(Icons.folder_open),
            label: const Text('Split a folder…'),
          ),
        ],
      ),
    ],
  );
}

/// The batch: every recording of the chosen folder, where each one stands,
/// and — once the splitting is done — the question only the operator may
/// answer: publish the clean ones, or review first.
class _BatchPanel extends StatelessWidget {
  const _BatchPanel({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  Color _tint(ThemeData theme, BatchStatus status) => switch (status) {
    BatchStatus.clean => theme.colorScheme.primary,
    BatchStatus.published => theme.colorScheme.secondary,
    BatchStatus.suspect => theme.colorScheme.tertiary,
    BatchStatus.mismatch || BatchStatus.failed => theme.colorScheme.error,
    BatchStatus.pending ||
    BatchStatus.splitting => theme.colorScheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<BatchEntry> batch = state.batch;
    final int done = batch
        .where(
          (BatchEntry e) =>
              e.status != BatchStatus.pending &&
              e.status != BatchStatus.splitting,
        )
        .length;
    final List<BatchEntry> attention = <BatchEntry>[
      for (final BatchEntry e in batch)
        if (e.needsAttention) e,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.folder_open, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Batch — ${state.batchFolder ?? ''} · $done of '
                  '${batch.length}'
                  '${state.batchRunning ? '…' : ' done'}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state.batchRunning)
                TextButton.icon(
                  onPressed: cubit.cancelBatch,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop after this file'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // One chip per recording: the surah number, tinted by where it
          // stands. A chip with a split opens it in the review list below —
          // that is the whole of "revise it first".
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (int i = 0; i < batch.length; i++)
                Tooltip(
                  message:
                      '${batch[i].fileName} — ${batch[i].status.name}'
                      '${batch[i].detail.isEmpty ? '' : '\n${batch[i].detail}'}',
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 6,
                    ),
                    side: BorderSide(color: _tint(theme, batch[i].status)),
                    avatar: batch[i].status == BatchStatus.splitting
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    label: Text(
                      batch[i].surahNumber == 0
                          ? batch[i].fileName
                          : '${batch[i].surahNumber}'
                                '${switch (batch[i].status) {
                                  BatchStatus.clean => ' ✓',
                                  BatchStatus.published => ' ↑',
                                  BatchStatus.suspect => ' ?',
                                  BatchStatus.mismatch || BatchStatus.failed => ' ✗',
                                  _ => '',
                                }}',
                      style: TextStyle(
                        fontSize: 12,
                        color: _tint(theme, batch[i].status),
                      ),
                    ),
                    onPressed: batch[i].plan == null
                        ? null
                        : () => cubit.openBatchEntry(i),
                  ),
                ),
            ],
          ),
          // What needs an ear or a hand, spelled out — the same words the
          // folder's README.md carries.
          if (attention.isNotEmpty && !state.batchRunning) ...<Widget>[
            const SizedBox(height: 8),
            for (final BatchEntry entry in attention)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: SelectableText(
                  '${entry.fileName}'
                  '${entry.surahNumber > 0 ? ' (surah ${entry.surahNumber})' : ''}'
                  ' — ${entry.detail}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _tint(theme, entry.status),
                  ),
                ),
              ),
          ],
          if (state.batchAwaitsDecision) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: () => _confirmPublish(context),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    'Publish the ${state.batchClean.length} clean surah'
                    '${state.batchClean.length == 1 ? '' : 's'}…',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Or open any chip above and review it first. Only the '
                    'clean ones upload — the rest stay here and in the '
                    "folder's README.md. A fix made by ear turns its chip "
                    'clean, and "Publish to R2" under an open surah '
                    'publishes that surah alone.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Publishing is the one step that cannot be taken back — the tool cannot
  /// delete from R2 — so the batch, like everything irreversible here, asks
  /// in words before it acts.
  Future<void> _confirmPublish(BuildContext context) async {
    final int clips = state.batchClean.fold<int>(
      0,
      (int sum, BatchEntry e) => sum + (e.plan?.published.length ?? 0),
    );
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Publish the batch?'),
        content: Text(
          '${state.batchClean.length} surahs — $clips clips and their packs — '
          'upload to R2 under "${state.reciterId}", and the manifest is '
          'published once at the end. Uploaded audio cannot be deleted by '
          'this tool, only replaced with a version bump.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (go ?? false) await cubit.publishBatch();
  }
}

/// Adds a reciter to the manifest: names, riwayah, portrait.
///
/// This is the whole of "adding a reciter" — no app release, no `reciters.json`
/// edit. The app merges the manifest's reciters into its own catalog on every
/// launch, so one published manifest is enough for them to appear, portrait
/// and all.
class _AddReciterDialog extends StatefulWidget {
  const _AddReciterDialog({required this.cubit});

  final AdminCubit cubit;

  static Future<void> show(BuildContext context, AdminCubit cubit) =>
      showDialog<void>(
        context: context,
        builder: (_) => _AddReciterDialog(cubit: cubit),
      );

  @override
  State<_AddReciterDialog> createState() => _AddReciterDialogState();
}

class _AddReciterDialogState extends State<_AddReciterDialog> {
  final TextEditingController _id = TextEditingController();
  final TextEditingController _nameAr = TextEditingController();
  final TextEditingController _nameEn = TextEditingController();
  final TextEditingController _riwayah = TextEditingController();
  String? _imagePath;

  @override
  void dispose() {
    _id.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _riwayah.dispose();
    super.dispose();
  }

  bool get _isComplete =>
      _id.text.trim().isNotEmpty &&
      _nameAr.text.trim().isNotEmpty &&
      _nameEn.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a reciter'),
    content: SizedBox(
      width: 420,
      // Scrollable: five fields and a button do not fit a short window, and a
      // dialog that overflows hides its own confirm button.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _id,
              decoration: const InputDecoration(
                labelText: 'id',
                helperText:
                    'Lowercase, no spaces — it becomes part of every '
                    'path on the CDN and can never change',
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _nameAr,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'Name (Arabic)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _nameEn,
              decoration: const InputDecoration(labelText: 'Name (English)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _riwayah,
              decoration: const InputDecoration(
                labelText: 'Riwayah (optional)',
                hintText: 'hafs',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () async {
                    final String? path = await widget.cubit.chooseImage();
                    if (path != null) setState(() => _imagePath = path);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_imagePath == null ? 'Portrait…' : 'Change…'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _imagePath == null
                        ? 'No portrait — the app shows their initial'
                        : p.basename(_imagePath!),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _isComplete
            ? () {
                widget.cubit.addReciter(
                  id: _id.text,
                  nameAr: _nameAr.text,
                  nameEn: _nameEn.text,
                  riwayah: _riwayah.text,
                  imageFilePath: _imagePath,
                );
                Navigator.of(context).pop();
              }
            : null,
        child: const Text('Add and publish'),
      ),
    ],
  );
}

/// The recording, chosen through the system file panel.
///
/// A button and a file name rather than a path field: the operator picks a
/// recording dozens of times a session, and typing a path each time is the
/// kind of friction that ends in a typo pointing at last week's take.
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? path = state.sourcePath;

    return SizedBox(
      width: 360,
      child: Row(
        children: <Widget>[
          OutlinedButton.icon(
            onPressed: cubit.chooseSource,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(path == null ? 'Choose recording…' : 'Change…'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: path == null
                ? Text(
                    'No recording chosen',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                // The name is what the operator recognises; the full path is
                // there on hover for when two takes share a name.
                : Tooltip(
                    message: path,
                    child: Text(
                      p.basename(path),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The guard's verdict, and the only way past it.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    final PublishDecision decision = state.decision;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${plan.actualCount} segments · expected ${plan.expectedCount}'
          ' (${plan.expectsIstiadhah ? "isti'adhah + " : ''}'
          '${plan.expectsBasmala ? 'basmala + ' : ''}'
          '${plan.surah.ayahCount} ayahs)',
          style: theme.textTheme.titleSmall,
        ),
        if (plan.countMatches) ...<Widget>[
          const SizedBox(height: 4),
          // The count matching says nothing about where the cuts fell. This
          // does: each clip's length against the words it is meant to hold.
          Text(
            state.suspects.isEmpty
                ? 'Every clip fits its text.'
                : '${state.suspects.length} clip'
                      '${state.suspects.length == 1 ? '' : 's'} do not fit '
                      'their text — marked below. Listen to them before '
                      'publishing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: state.suspects.isEmpty
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        ],
        if (!plan.countMatches) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Override reason (required to publish a mismatch)',
              helperText:
                  'Recorded in the log with the upload. Say what is different '
                  'and why it is right.',
            ),
            onChanged: cubit.setOverrideReason,
          ),
        ],
        const SizedBox(height: 8),
        // Only worth offering once something is actually in the way, and even
        // then it says what it costs.
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          value: state.replaceExisting,
          onChanged: (bool? value) => cubit.setReplaceExisting(value ?? false),
          title: const Text('Overwrite paths that already hold audio'),
          subtitle: const Text(
            'Only for a surah that was uploaded but never named in a published '
            'manifest — nobody can have downloaded it yet. Otherwise publish a '
            'new path and bump the version.',
          ),
        ),
        Row(
          children: <Widget>[
            FilledButton(
              onPressed: state.canPublish ? () => cubit.publish() : null,
              child: const Text('Publish to R2'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                switch (decision) {
                  PublishAllowed() => 'The split matches the catalog.',
                  PublishOverridden(summary: final String s) =>
                    'Publishing with an override: $s',
                  PublishBlocked(reason: final String r) => r,
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: decision is PublishBlocked
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the review list is showing, and the two things that act on all of it:
/// narrowing it to the clips worth listening to, and taking an edit back.
class _ReviewBar extends StatelessWidget {
  const _ReviewBar({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SegmentPlan plan = state.plan!;
    final ThemeData theme = Theme.of(context);
    final int suspects = state.suspects.length;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Text(
            '${plan.actualCount} clip${plan.actualCount == 1 ? '' : 's'}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(width: 12),
          // Al-Baqarah reviews as 286 rows and the handful worth hearing are
          // scattered through them; scrolling for a marked row is how one
          // gets missed. Kept on screen while the filter is on even once
          // nothing is left to show, so it can be turned off again.
          if (suspects > 0 || state.onlySuspects)
            FilterChip(
              selected: state.onlySuspects,
              onSelected: cubit.setOnlySuspects,
              avatar: const Icon(Icons.filter_alt_outlined, size: 18),
              label: Text(
                suspects == 0
                    ? 'None left that do not fit'
                    : 'Only the $suspects that do not fit',
              ),
            ),
          const Spacer(),
          if (state.previewingIndex != null)
            TextButton.icon(
              onPressed: cubit.stopPreview,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          TextButton.icon(
            // Cutting by ear is a sequence of guesses; without this a merge or
            // a drop could only be taken back by splitting the surah again,
            // which loses every other edit with it.
            onPressed: state.canUndo ? cubit.undo : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
          ),
        ],
      ),
    );
  }
}

/// One row per segment, with the ayah it will be published as.
class _Review extends StatelessWidget {
  const _Review({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) {
      return const Center(
        child: Text('Pick a recording and a surah, then split.'),
      );
    }

    final List<PlannedSegment> planned = plan.planned;
    // Filtered by index rather than by building a shorter list: every row
    // keeps its own number, because a row that says "ayah 7" while sitting
    // fifth is how the wrong segment gets edited.
    final List<int> shown = <int>[
      for (int i = 0; i < planned.length; i++)
        if (!state.onlySuspects || state.suspects.contains(i)) i,
    ];

    if (shown.isEmpty) {
      return const Center(
        child: Text('Every clip fits its text — nothing left to listen to.'),
      );
    }

    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int position) => _SegmentRow(
        state: state,
        cubit: cubit,
        plan: plan,
        index: shown[position],
      ),
    );
  }
}

/// One segment: what it will be published as, the ayah it should hold, and
/// everything that can be done to it by ear.
class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.state,
    required this.cubit,
    required this.plan,
    required this.index,
  });

  final AdminState state;
  final AdminCubit cubit;
  final SegmentPlan plan;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlannedSegment item = plan.planned[index];
    final int? ayahNumber = plan.ayahNumberFor(index);
    final Ayah? ayah = ayahNumber == null
        ? null
        : state.ayahs.where((Ayah a) => a.number == ayahNumber).firstOrNull;
    final bool playing = state.previewingIndex == index;
    final bool suspect = state.suspects.contains(index);
    final bool last = index == plan.segments.length - 1;

    return ListTile(
      // The row being heard is marked, not just its button: with the list
      // scrolled away from the play that started it, the icon alone is not
      // findable.
      tileColor: playing
          ? theme.colorScheme.primary.withValues(alpha: 0.08)
          : null,
      leading: SizedBox(
        width: 92,
        child: Text(
          item.isIstiadhah
              ? "isti'adhah\nnot published"
              : item.isBasmala
              ? 'basmala\n000'
              : '${item.ayahNumber}\n'
                    '${_pad3(plan.surah.number)}${_pad3(item.ayahNumber)}',
          style: const TextStyle(fontFeatures: <FontFeature>[]),
        ),
      ),
      title: Directionality(
        textDirection: TextDirection.rtl,
        // The one widget allowed to render Quranic text, and the text is
        // whatever quran.db holds — nothing on this path touches it.
        child: ayah == null
            ? Text(
                item.isIstiadhah
                    ? "— the isti'adhah; cut off, not published —"
                    : '— the basmala; not an ayah row —',
              )
            : AyahText(text: ayah.text, fontSize: 22),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${_time(item.segment.start)} → ${_time(item.segment.end)}  '
            '(${(item.segment.duration.inMilliseconds / 1000).toStringAsFixed(2)} s)'
            '${suspect ? '   — length does not fit the text' : ''}'
            // A gap is a deliberate deletion, so it is shown where it is.
            '${plan.gapAfter(index) > Duration.zero ? '   · ${(plan.gapAfter(index).inMilliseconds / 1000).toStringAsFixed(2)} s cut out after this' : ''}',
            style: TextStyle(
              // A segment under a second is almost always a fragment of
              // silence rather than an ayah, and a count that matches can
              // still be wrong — the guard counts, it does not listen.
              color:
                  item.segment.duration < const Duration(seconds: 1) || suspect
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          // Where the playhead is inside this clip. Subscribed to by the one
          // row that is playing, so a position ticking five times a second
          // does not rebuild a list of 286 rows.
          if (playing) ...<Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6, end: 24),
              child: StreamBuilder<double>(
                stream: cubit.previewProgress,
                builder: (BuildContext context, AsyncSnapshot<double> at) =>
                    LinearProgressIndicator(value: at.data ?? 0, minHeight: 3),
              ),
            ),
            Row(
              children: <Widget>[
                // The ear finds a missed break faster than any threshold
                // does: press it the moment the next ayah starts and the cut
                // lands there, no timecode read off a bar and typed back in.
                TextButton.icon(
                  onPressed: cubit.cutAtPlayhead,
                  icon: const Icon(Icons.content_cut, size: 14),
                  label: const Text('Cut at the playhead'),
                ),
                const SizedBox(width: 12),
                // Where the playhead is, as a time in the recording — the
                // same clock the boundary fields speak, so a moment heard
                // here can be typed there. Tabular figures, or the ticking
                // digits would shiver the whole line.
                StreamBuilder<Duration>(
                  stream: cubit.previewPlayhead,
                  builder: (BuildContext context, AsyncSnapshot<Duration> at) =>
                      Text(
                        at.data == null ? '' : 'at ${formatTimecode(at.data!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            // Straight from the recording, between this row's two times:
            // nothing is encoded to listen, so an edit is heard at once.
            tooltip: playing ? 'Stop' : 'Play this segment',
            onPressed: () => cubit.previewSegment(index),
            icon: Icon(
              playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            // The edit that needs no pause to land on: where a reciter
            // runs one ayah into the next, the only way to a right cut
            // is to listen and say where it goes.
            tooltip: 'Edit start and end',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => BlocProvider<AdminCubit>.value(
                value: cubit,
                child: _BoundaryEditor(index: index),
              ),
            ),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            // Cuts at the quietest moment inside the segment, not at its
            // midpoint: halving a segment lands the cut wherever the
            // arithmetic falls, which is usually inside a word.
            tooltip: 'Split at the quietest point',
            onPressed: () => cubit.splitSegment(index),
            icon: const Icon(Icons.content_cut),
          ),
          IconButton(
            // The other direction, and the repair for a pause *inside* an
            // ayah that the splitter read as the end of one. Without it the
            // only control for that was dropping half the ayah.
            tooltip: last
                ? 'Nothing after this to join it to'
                : 'Join with the clip after it',
            onPressed: last ? null : () => cubit.mergeSegment(index),
            icon: const Icon(Icons.merge_type),
          ),
          IconButton(
            tooltip:
                'Drop this clip — its audio goes into no file, and every '
                'ayah after it shifts up one',
            onPressed: () => cubit.removeSegment(index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  static String _pad3(int n) => n.toString().padLeft(3, '0');

  static String _time(Duration d) => formatTimecode(d);
}

/// Start and end of one segment, editable by ear.
///
/// Every change goes to the cubit at once rather than waiting for a Save: the
/// play buttons in here have to play what the fields now say, and the list
/// behind the dialog re-checks the clip against its text as it moves. The
/// start of a segment is the end of the one before it, so moving either moves
/// both — there is never a gap or an overlap to tidy up afterwards.
class _BoundaryEditor extends StatefulWidget {
  const _BoundaryEditor({required this.index});

  final int index;

  @override
  State<_BoundaryEditor> createState() => _BoundaryEditorState();
}

class _BoundaryEditorState extends State<_BoundaryEditor> {
  /// Whether moving an edge takes the neighbouring segment with it. Both start
  /// joined every time the editor opens: a cut in the wrong place is the
  /// common case, and joined is the mode that cannot lose audio by accident.
  bool _startJoined = true;
  bool _endJoined = true;

  int get index => widget.index;

  @override
  Widget build(BuildContext context) => BlocBuilder<AdminCubit, AdminState>(
    builder: (BuildContext context, AdminState state) {
      final AdminCubit cubit = context.read<AdminCubit>();
      final SegmentPlan? plan = state.plan;
      if (plan == null || index >= plan.segments.length) {
        return const AlertDialog(content: Text('That segment is gone.'));
      }

      final PlannedSegment item = plan.planned[index];
      final bool suspect = state.suspects.contains(index);
      final ThemeData theme = Theme.of(context);

      return AlertDialog(
        title: Text(
          item.isIstiadhah
              ? "isti'adhah"
              : item.isBasmala
              ? 'basmala'
              : 'Ayah ${item.ayahNumber}',
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _BoundaryField(
                label: 'Start',
                value: item.segment.start,
                onChanged: (Duration to) => cubit.moveEdge(
                  index,
                  SegmentEdge.start,
                  to,
                  joined: _startJoined,
                ),
                onNudge: (Duration by) => cubit.nudgeEdge(
                  index,
                  SegmentEdge.start,
                  by,
                  joined: _startJoined,
                ),
                // Listening is the only honest way to find a boundary, so the
                // boundary can be set to the very moment being heard. Only
                // while something is playing: otherwise there is no moment.
                onSetToPlayhead: state.previewingIndex == null
                    ? null
                    : () => cubit.setEdgeToPlayhead(
                        index,
                        SegmentEdge.start,
                        joined: _startJoined,
                      ),
              ),
              if (index > 0)
                _JoinSwitch(
                  value: _startJoined,
                  onChanged: (bool v) => setState(() => _startJoined = v),
                  joinedLabel: 'Also moves the end of the segment before',
                  cutLabel:
                      'Only this segment — what is left before it is cut out',
                  cut: plan.gapAfter(index - 1),
                ),
              const SizedBox(height: 12),
              _BoundaryField(
                label: 'End',
                value: item.segment.end,
                onChanged: (Duration to) => cubit.moveEdge(
                  index,
                  SegmentEdge.end,
                  to,
                  joined: _endJoined,
                ),
                onNudge: (Duration by) => cubit.nudgeEdge(
                  index,
                  SegmentEdge.end,
                  by,
                  joined: _endJoined,
                ),
                onSetToPlayhead: state.previewingIndex == null
                    ? null
                    : () => cubit.setEdgeToPlayhead(
                        index,
                        SegmentEdge.end,
                        joined: _endJoined,
                      ),
              ),
              if (index < plan.segments.length - 1)
                _JoinSwitch(
                  value: _endJoined,
                  onChanged: (bool v) => setState(() => _endJoined = v),
                  joinedLabel: 'Also moves the start of the segment after',
                  cutLabel:
                      'Only this segment — what is left after it is cut out',
                  cut: plan.gapAfter(index),
                ),
              const SizedBox(height: 12),
              Text(
                '${(item.segment.duration.inMilliseconds / 1000).toStringAsFixed(2)} s'
                '${suspect ? ' — length does not fit the text' : ' — fits its text'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: suspect
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () =>
                        cubit.previewSegment(index, part: PreviewPart.opening),
                    icon: const Icon(Icons.first_page),
                    label: const Text('First 3 s'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        cubit.previewSegment(index, part: PreviewPart.ending),
                    icon: const Icon(Icons.last_page),
                    label: const Text('Last 3 s'),
                  ),
                  OutlinedButton.icon(
                    // The tail of the ayah before running into this one's
                    // opening: the other half of the same question, and the
                    // one the end preview cannot answer.
                    onPressed: () => cubit.previewSegment(
                      index,
                      part: PreviewPart.acrossStart,
                    ),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Across the start'),
                  ),
                  OutlinedButton.icon(
                    // The end of this ayah and the start of the next: how a
                    // boundary a word early or late actually sounds.
                    onPressed: () => cubit.previewSegment(
                      index,
                      part: PreviewPart.acrossEnd,
                    ),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Across the end'),
                  ),
                  OutlinedButton.icon(
                    // Keyed on this row, not on "is anything playing": with
                    // the old test a preview of the opening left this button
                    // saying Stop, and pressing it played nothing.
                    onPressed: state.previewingIndex == index
                        ? cubit.stopPreview
                        : () => cubit.previewSegment(index),
                    icon: Icon(
                      state.previewingIndex == index
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      state.previewingIndex == index ? 'Stop' : 'Whole segment',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              cubit.stopPreview();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}

/// One boundary: a time that can be typed, and four nudges.
class _BoundaryField extends StatefulWidget {
  const _BoundaryField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onNudge,
    this.onSetToPlayhead,
  });

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onNudge;

  /// Moves this boundary to where playback is right now. Null while nothing
  /// is playing, which is what disables the button.
  final VoidCallback? onSetToPlayhead;

  @override
  State<_BoundaryField> createState() => _BoundaryFieldState();
}

class _BoundaryFieldState extends State<_BoundaryField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatTimecode(widget.value),
  );

  /// A time typed and then left — by clicking a play button, or Done — used
  /// to be thrown away silently, because only Enter applied it. Leaving the
  /// field is as clear a "that is the number" as pressing Enter is.
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);
  bool _invalid = false;

  void _onFocusChange() {
    if (!_focus.hasFocus) _submit(_controller.text);
  }

  @override
  void didUpdateWidget(_BoundaryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A nudge, or a value the plan held back from passing its neighbour: show
    // where the boundary actually is, not what was typed.
    if (oldWidget.value != widget.value) {
      _controller.text = formatTimecode(widget.value);
      _invalid = false;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (!mounted) return;
    final Duration? parsed = parseTimecode(text);
    setState(() => _invalid = parsed == null);
    if (parsed == null) return;
    widget.onChanged(parsed);
    // If the plan clamped it, didUpdateWidget will not fire for an unchanged
    // value, so put the real position back by hand.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.text = formatTimecode(widget.value);
    });
  }

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: 'mm:ss.mmm or seconds — Enter, or just leave the field',
            errorText: _invalid ? 'Not a time' : null,
          ),
          onSubmitted: _submit,
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Set to the playhead — the moment being heard right now',
        onPressed: widget.onSetToPlayhead,
        icon: const Icon(Icons.my_location, size: 18),
      ),
      for (final int ms in <int>[-500, -100, 100, 500])
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(52, 40),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
            ),
            onPressed: () => widget.onNudge(Duration(milliseconds: ms)),
            child: Text(
              '${ms > 0 ? '+' : ''}${(ms / 1000).toStringAsFixed(1)}',
            ),
          ),
        ),
    ],
  );
}

/// Whether an edge takes its neighbour with it.
///
/// Says what each answer does rather than naming a mode, and says how much
/// audio is currently being left out — a gap is a deliberate deletion, and it
/// should never be possible to have made one without seeing it.
class _JoinSwitch extends StatelessWidget {
  const _JoinSwitch({
    required this.value,
    required this.onChanged,
    required this.joinedLabel,
    required this.cutLabel,
    required this.cut,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String joinedLabel;
  final String cutLabel;

  /// How much audio sits between the two segments right now.
  final Duration cut;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (bool? v) => onChanged(v ?? true),
          title: Text(value ? joinedLabel : cutLabel),
        ),
        if (cut > Duration.zero)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 40, bottom: 4),
            child: Text(
              '${(cut.inMilliseconds / 1000).toStringAsFixed(2)} s between '
              'them is cut out and goes into no clip.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }
}
