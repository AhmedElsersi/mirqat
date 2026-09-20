import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/app_info.dart';
import '../cubit/app_info_editor_cubit.dart';
import '../services/app_info_validator.dart';

/// Edits `app.json`: About us, Our goal, the developer's card, and the update
/// rules for each store.
///
/// A workbench form, like the rest of the tool: English labels, no
/// localisation, everything on one scrolling page with the problems and the
/// publish button pinned at the foot.
class AppInfoEditorScreen extends StatelessWidget {
  const AppInfoEditorScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<AppInfoEditorCubit, AppInfoEditorState>(
        builder: (BuildContext context, AppInfoEditorState state) {
          final AppInfoEditorCubit cubit = context.read<AppInfoEditorCubit>();
          return Scaffold(
            appBar: AppBar(
              title: const Text('Mirqat — app.json'),
              bottom: state.busy
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(4),
                      child: LinearProgressIndicator(),
                    )
                  : null,
              actions: <Widget>[
                TextButton.icon(
                  onPressed: state.loading ? null : cubit.load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload what is live'),
                ),
                TextButton.icon(
                  onPressed: state.loading
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: cubit.json));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('JSON copied.')),
                          );
                        },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy JSON'),
                ),
              ],
            ),
            body: state.loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: <Widget>[
                      Expanded(
                        // Keyed by what was loaded: the fields hold their
                        // own text, and a reload has to replace it.
                        child: _Form(
                          key: ValueKey<AppInfo>(state.published),
                          state: state,
                          cubit: cubit,
                        ),
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
  const _Form({required this.state, required this.cubit, super.key});

  final AppInfoEditorState state;
  final AppInfoEditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final AppInfo d = state.draft;

    // A column in a scroll view, not a lazy list: a field scrolled out of a
    // lazy list is disposed, and with it the caret and the undo history of
    // whatever was being typed there.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(switch (state.source) {
            AppInfoSource.published =>
              'Loaded from the Pages site: this is what the app shows now.',
            AppInfoSource.bundled =>
              'Nothing is published yet, or the site could not be reached: '
                  'this is the copy bundled with the app.',
          }, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          _Section(
            title: 'About us',
            children: <Widget>[
              _Bilingual(
                value: d.about,
                lines: 5,
                onChanged: (LocalizedText t) =>
                    cubit.edit((AppInfo i) => i.copyWith(about: t)),
              ),
            ],
          ),
          _Section(
            title: 'Our goal',
            children: <Widget>[
              _Bilingual(
                value: d.goal,
                lines: 5,
                onChanged: (LocalizedText t) =>
                    cubit.edit((AppInfo i) => i.copyWith(goal: t)),
              ),
            ],
          ),
          _Section(
            title: 'The developer',
            children: <Widget>[
              _Bilingual(
                value: d.developer.name,
                label: 'Name',
                onChanged: (LocalizedText t) => cubit.edit(
                  (AppInfo i) =>
                      i.copyWith(developer: i.developer.copyWith(name: t)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: state.busy ? null : cubit.choosePhoto,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      d.developer.photo.isEmpty ? 'Photo…' : 'Change photo…',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      d.developer.photo.isEmpty
                          ? 'No photo — the card shows the name\'s first letter.'
                          : d.developer.photo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (d.developer.photo.isNotEmpty)
                    IconButton(
                      onPressed: cubit.removePhoto,
                      tooltip: 'Remove the photo',
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              for (final DeveloperLink link in DeveloperLink.values)
                _Field(
                  label: switch (link) {
                    DeveloperLink.email => 'Email',
                    DeveloperLink.github => 'GitHub',
                    DeveloperLink.linkedin => 'LinkedIn',
                    DeveloperLink.whatsapp =>
                      'WhatsApp (number, or wa.me link)',
                    DeveloperLink.facebook => 'Facebook',
                  },
                  hint: 'Left blank, it is not shown.',
                  value: d.developer.links[link] ?? '',
                  onChanged: (String v) => cubit.edit(
                    (AppInfo i) =>
                        i.copyWith(developer: i.developer.withLink(link, v)),
                  ),
                ),
            ],
          ),
          _Section(
            title: 'Updates',
            children: <Widget>[
              Text(
                'Below the minimum, the app shows a page asking to be updated '
                'and nothing else. Below the latest, it mentions the update and '
                'can be told "later". Blank means no rule. Versions are the '
                'store\'s: 1.4.0.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _Platform(
                name: 'Android',
                value: d.update.android,
                onChanged: (PlatformUpdate u) => cubit.edit(
                  (AppInfo i) =>
                      i.copyWith(update: i.update.copyWith(android: u)),
                ),
              ),
              const SizedBox(height: 8),
              _Platform(
                name: 'iOS',
                value: d.update.ios,
                onChanged: (PlatformUpdate u) => cubit.edit(
                  (AppInfo i) => i.copyWith(update: i.update.copyWith(ios: u)),
                ),
              ),
              const SizedBox(height: 8),
              _Bilingual(
                value: d.update.notes,
                label: 'What is new (optional)',
                lines: 3,
                onChanged: (LocalizedText t) => cubit.edit(
                  (AppInfo i) =>
                      i.copyWith(update: i.update.copyWith(notes: t)),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// Arabic and English side by side. The Arabic box is right-to-left whatever
/// the tool's own direction, so that what is typed reads as it will be shown.
class _Bilingual extends StatelessWidget {
  const _Bilingual({
    required this.value,
    required this.onChanged,
    this.label,
    this.lines = 1,
  });

  final LocalizedText value;
  final ValueChanged<LocalizedText> onChanged;
  final String? label;
  final int lines;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: _Field(
          label: '${label == null ? '' : '$label — '}English',
          value: value.en,
          lines: lines,
          onChanged: (String v) => onChanged(value.copyWith(en: v)),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Field(
          label: '${label == null ? '' : '$label — '}Arabic',
          value: value.ar,
          lines: lines,
          textDirection: TextDirection.rtl,
          onChanged: (String v) => onChanged(value.copyWith(ar: v)),
        ),
      ),
    ],
  );
}

class _Platform extends StatelessWidget {
  const _Platform({
    required this.name,
    required this.value,
    required this.onChanged,
  });

  final String name;
  final PlatformUpdate value;
  final ValueChanged<PlatformUpdate> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(name, style: Theme.of(context).textTheme.titleSmall),
        ),
      ),
      Expanded(
        child: _Field(
          label: 'Minimum (blocks below it)',
          value: value.min,
          onChanged: (String v) => onChanged(value.copyWith(min: v.trim())),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _Field(
          label: 'Latest (mentions below it)',
          value: value.latest,
          onChanged: (String v) => onChanged(value.copyWith(latest: v.trim())),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 3,
        child: _Field(
          label: 'Store page (https)',
          value: value.storeUrl,
          onChanged: (String v) =>
              onChanged(value.copyWith(storeUrl: v.trim())),
        ),
      ),
    ],
  );
}

/// A text field that owns its controller: seeded once from [value], then the
/// source of truth for its own text, so that typing is never fought by a
/// rebuild putting the caret back at the start.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.lines = 1,
    this.textDirection,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int lines;
  final TextDirection? textDirection;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: _controller,
      minLines: widget.lines,
      maxLines: widget.lines == 1 ? 1 : null,
      textDirection: widget.textDirection,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    ),
  );
}

/// What is wrong, what happened last, and the way out: publish, or revert.
class _Footer extends StatefulWidget {
  const _Footer({required this.state, required this.cubit});

  final AppInfoEditorState state;
  final AppInfoEditorCubit cubit;

  @override
  State<_Footer> createState() => _FooterState();
}

class _FooterState extends State<_Footer> {
  final TextEditingController _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppInfoEditorState state = widget.state;
    final List<String> problems = state.problems;
    final Map<String, String> raised = state.raised;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final String problem in problems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                '• $problem',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (problems.isEmpty && raised.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      'This raises a minimum: '
                      '${raised.entries.map((MapEntry<String, String> e) => '${e.key} to ${e.value}').join(', ')}. '
                      'Every install below it will be able to do nothing but '
                      'update. Type ${confirmationFor(raised)} to confirm.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _confirm,
                      decoration: const InputDecoration(
                        labelText: 'Confirm',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          if (state.error != null)
            SelectableText(
              state.error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (state.message != null) SelectableText(state.message!),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed:
                    state.busy ||
                        !state.dirty ||
                        problems.isNotEmpty ||
                        (raised.isNotEmpty &&
                            _confirm.text.trim() != confirmationFor(raised))
                    ? null
                    : () => widget.cubit.publish(
                        typedConfirmation: _confirm.text,
                      ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Publish app.json'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: state.busy || !state.dirty
                    ? null
                    : widget.cubit.revert,
                child: const Text('Revert'),
              ),
              const SizedBox(width: 12),
              if (!state.dirty)
                Text('Nothing changed.', style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
