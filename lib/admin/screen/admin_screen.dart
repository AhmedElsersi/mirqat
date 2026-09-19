import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../core/state/load_status.dart';
import '../../core/widgets/ayah_text.dart';
import '../../data/models/ayah.dart';
import '../../data/models/surah.dart';
import '../cubit/admin_cubit.dart';
import '../cubit/admin_state.dart';
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
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<AdminCubit, AdminState>(
    builder: (BuildContext context, AdminState state) {
      final AdminCubit cubit = context.read<AdminCubit>();

      return Scaffold(
        appBar: AppBar(
          title: const Text('Mirqat — audio admin'),
          bottom: state.progress == null
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Setup(state: state, cubit: cubit),
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
        const Divider(),
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
  );
}

class _Setup extends StatelessWidget {
  const _Setup({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) => Wrap(
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
              state.reciters.any((AdminReciter r) => r.id == state.reciterId)
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
          onChanged: (String? id) => id == null ? null : cubit.setReciterId(id),
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
              state.surah?.bismillahMode == BismillahMode.separatePreamble &&
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
    ],
  );
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

    return ListView.separated(
      itemCount: planned.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final PlannedSegment item = planned[index];
        final int? ayahNumber = plan.ayahNumberFor(index);
        final Ayah? ayah = ayahNumber == null
            ? null
            : state.ayahs.where((Ayah a) => a.number == ayahNumber).firstOrNull;

        return ListTile(
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
          subtitle: Text(
            '${_time(item.segment.start)} → ${_time(item.segment.end)}  '
            '(${(item.segment.duration.inMilliseconds / 1000).toStringAsFixed(2)} s)'
            '${state.suspects.contains(index) ? '   — length does not fit the text' : ''}'
            // A gap is a deliberate deletion, so it is shown where it is.
            '${plan.gapAfter(index) > Duration.zero ? '   · ${(plan.gapAfter(index).inMilliseconds / 1000).toStringAsFixed(2)} s cut out after this' : ''}',
            style: TextStyle(
              // A segment under a second is almost always a fragment of
              // silence rather than an ayah, and a count that matches can
              // still be wrong — the guard counts, it does not listen.
              color:
                  item.segment.duration < const Duration(seconds: 1) ||
                      state.suspects.contains(index)
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                // Straight from the recording, between this row's two times:
                // nothing is encoded to listen, so an edit is heard at once.
                tooltip: state.previewingIndex == index
                    ? 'Stop'
                    : 'Play this segment',
                onPressed: () => cubit.previewSegment(index),
                icon: Icon(
                  state.previewingIndex == index
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
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
                tooltip: 'Drop this segment',
                onPressed: () => cubit.removeSegment(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
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
                    onPressed: state.previewingIndex == null
                        ? () => cubit.previewSegment(index)
                        : cubit.stopPreview,
                    icon: Icon(
                      state.previewingIndex == null
                          ? Icons.play_arrow
                          : Icons.stop,
                    ),
                    label: Text(
                      state.previewingIndex == null ? 'Whole segment' : 'Stop',
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
  });

  final String label;
  final Duration value;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onNudge;

  @override
  State<_BoundaryField> createState() => _BoundaryFieldState();
}

class _BoundaryFieldState extends State<_BoundaryField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatTimecode(widget.value),
  );
  bool _invalid = false;

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
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
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
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: 'mm:ss.mmm or seconds — Enter to apply',
            errorText: _invalid ? 'Not a time' : null,
          ),
          onSubmitted: _submit,
        ),
      ),
      const SizedBox(width: 8),
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
