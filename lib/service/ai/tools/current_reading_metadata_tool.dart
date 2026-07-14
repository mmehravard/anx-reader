import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';

import 'base_tool.dart';

class CurrentReadingMetadataTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CurrentReadingMetadataTool(this._conversation)
      : super(
          name: 'current_reading_metadata',
          description:
              'Fetch up-to-date metadata about the active reading session. Use when you need book identifiers, progress, chapter details, or to confirm whether the user is currently reading. Returns flags for reading state plus book, progress, and chapter objects when available.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': <String, dynamic>{},
          },
          timeout: const Duration(seconds: 2),
        );

  final AiConversationContext _conversation;

  @override
  JsonMap parseInput(Map<String, dynamic> json) {
    return json;
  }

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    final state = _conversation.readingState;
    final book = _conversation.book;

    if (book == null) {
      return {
        'isReading': false,
        'message': 'This conversation is not associated with a book.',
      };
    }

    return {
      'isReading': state?.isReading == true,
      'book': {
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'groupId': book.groupId,
        'description': book.description,
        'rating': book.rating,
        'coverPath': book.coverPath,
        'filePath': book.filePath,
        'lastReadPosition': book.lastReadPosition,
        'readingPercentage': book.readingPercentage,
        'md5': book.md5,
        'createTime': book.createTime.toIso8601String(),
        'updateTime': book.updateTime.toIso8601String(),
      },
      'progress': state == null
          ? null
          : {
              'percentage': state.percentage,
              'cfi': state.cfi,
            },
      'chapter': state == null
          ? null
          : {
              'title': state.chapterTitle,
              'href': state.chapterHref,
              'currentPage': state.chapterCurrentPage,
              'totalPages': state.chapterTotalPages,
            },
    };
  }
}

final AiToolDefinition currentReadingMetadataToolDefinition = AiToolDefinition(
  id: 'current_reading_metadata',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCurrentReadingMetadataName,
  descriptionBuilder: (L10n l10n) =>
      l10n.aiToolCurrentReadingMetadataDescription,
  build: (context) => CurrentReadingMetadataTool(context.conversation).tool,
);
