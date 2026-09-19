import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../notes/audio_import.dart';
import '../notes/notes.dart';
import '../permissions/permissions.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';

@Preview(name: 'Home', size: Size(412, 915), wrapper: previewApp)
Widget homePreview() =>
    const HomeScreen(name: 'Ada Lovelace', email: 'ada@gmail.com');

/// Notes, and the two ways to add one. Everything else lives in settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  final String? name;
  final String email;
  final String? photoUrl;

  Future<void> _import(BuildContext context) async {
    final result = await importAudio();
    final error = result.error;
    if (error == null || !context.mounted) return;
    _say(context, error);
  }

  Future<void> _record(BuildContext context) async {
    var mic = await Permissions.micStatus();
    if (mic != MicPermission.granted) mic = await Permissions.requestMic();
    if (!context.mounted) return;
    if (mic != MicPermission.granted) {
      _say(
        context,
        "Carry can't record without the microphone. "
        'Turn it on in Settings → Permissions.',
      );
      return;
    }
    // ponytail: the button and its permission check are real; capturing audio
    // isn't built yet. Replace this line with the recorder.
    _say(context, 'Recording is coming next.');
  }

  void _say(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            iconSize: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tooltip: 'Import audio',
            onPressed: () => _import(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            iconSize: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(
                  name: name,
                  email: email,
                  photoUrl: photoUrl,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Note>>(
        valueListenable: Notes.all,
        builder: (context, notes, _) => notes.isEmpty
            ? const _EmptyNotes()
            : ListView.builder(
                // Room at the bottom so the record button never covers a note.
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 150),
                itemCount: notes.length,
                itemBuilder: (context, i) => _NoteTile(note: notes[i]),
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        // Sits well clear of the phone's gesture bar: there's no nav bar of
        // ours down there, and this is where the thumb lands.
        padding: const EdgeInsets.only(bottom: 44, right: 4),
        child: _RecordButton(onPressed: () => _record(context)),
      ),
    );
  }
}

/// The main action. Grows a little under a cursor and dips when pressed, so
/// it answers the pointer on a desktop or the web preview without moving on
/// the page.
class _RecordButton extends StatefulWidget {
  const _RecordButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed
        ? 0.96
        : _hovering
        ? 1.05
        : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        // Listener, not a gesture: the button keeps its own tap handling.
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: FloatingActionButton.extended(
            onPressed: widget.onPressed,
            backgroundColor: CarryColors.ink,
            foregroundColor: CarryColors.ground,
            shape: const StadiumBorder(),
            extendedPadding: const EdgeInsets.symmetric(horizontal: 36),
            extendedIconLabelSpacing: 0,
            elevation: 3,
            hoverElevation: 10,
            tooltip: 'Record',
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Record',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      key: ValueKey(note.id),
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'Not transcribed yet',
        style: text.bodySmall?.copyWith(color: CarryColors.muted),
      ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text('No notes yet', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Record one with the button below, or import a recording you '
            'already have.',
            style: text.bodyLarge?.copyWith(color: CarryColors.muted),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
