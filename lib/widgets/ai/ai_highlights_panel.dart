import 'package:anx_reader/constants/note_annotations.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiHighlightsPanel extends ConsumerStatefulWidget {
  const AiHighlightsPanel({
    super.key,
    required this.book,
    required this.onSend,
  });

  final Book book;
  final ValueChanged<String> onSend;

  @override
  ConsumerState<AiHighlightsPanel> createState() => _AiHighlightsPanelState();
}

class _AiHighlightsPanelState extends ConsumerState<AiHighlightsPanel> {
  final TextEditingController _instructionController = TextEditingController();
  final Set<int> _selectedNoteIds = {};

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  void _toggleSelection(BookNote note) {
    final id = note.id;
    if (id == null) return;
    setState(() {
      if (!_selectedNoteIds.add(id)) {
        _selectedNoteIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(bookNotesControllerProvider(widget.book));
    final theme = Theme.of(context);

    return notesState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(child: Text('Error: $error')),
      data: (state) {
        final highlights = state.allNotes
            .where(
                (note) => note.type == 'highlight' || note.type == 'underline')
            .toList(growable: false);
        final selectedHighlights = highlights
            .where(
                (note) => note.id != null && _selectedNoteIds.contains(note.id))
            .toList(growable: false);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select highlights to share with AI',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${selectedHighlights.length} selected',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: highlights.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'This book has no highlights yet.',
                          style: theme.textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: highlights.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final note = highlights[index];
                        return _AiHighlightTile(
                          note: note,
                          selected: note.id != null &&
                              _selectedNoteIds.contains(note.id),
                          onTap: () => _toggleSelection(note),
                        );
                      },
                    ),
            ),
            FilledContainer(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              radius: 15,
              child: Column(
                children: [
                  TextField(
                    controller: _instructionController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Add an instruction (optional)',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: selectedHighlights.isEmpty
                          ? null
                          : () => widget.onSend(
                                generatePromptWithHighlights(
                                  book: widget.book,
                                  highlights: selectedHighlights,
                                  instruction: _instructionController.text,
                                ),
                              ),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Send to AI'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AiHighlightTile extends StatelessWidget {
  const _AiHighlightTile({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final BookNote note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = Color(int.tryParse('0xff${note.color}') ?? 0xff555555);
    final option =
        notesType.where((type) => type.type == note.type).firstOrNull;

    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: FilledContainer(
          padding: const EdgeInsets.all(12),
          radius: 15,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(option?.icon ?? Icons.highlight, color: accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.content, style: theme.textTheme.bodyLarge),
                    if (note.readerNote?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(
                        note.readerNote!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (note.chapter.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(note.chapter, style: theme.textTheme.labelSmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color:
                    selected ? theme.colorScheme.primary : theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
