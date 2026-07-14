import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:langchain_core/chat_models.dart';

typedef ConversationBlockSummarizer = Future<String?> Function(String block);

/// Builds the bounded history sent to a model without changing the transcript
/// shown to the user or stored as the conversation record.
class ConversationMemory {
  const ConversationMemory();

  static const int recentMessageCount = 20;

  Future<List<ChatMessage>> buildPromptMessages({
    required String conversationId,
    required List<ChatMessage> messages,
    required ConversationBlockSummarizer summarize,
  }) async {
    if (messages.isEmpty) return const [];

    final currentMessage = messages.last;
    final previousMessages = messages.sublist(0, messages.length - 1);
    final recentStart = (previousMessages.length - recentMessageCount)
        .clamp(0, previousMessages.length);
    final olderMessages = previousMessages.sublist(0, recentStart);
    final recentMessages = previousMessages.sublist(recentStart);

    final existing = await AiHistoryStore.readSummaries(conversationId);
    final summaries = <String, AiConversationSummary>{
      for (final summary in existing)
        _rangeKey(summary.startSequence, summary.endSequence): summary,
    };
    final promptMessages = <ChatMessage>[];
    final rawRemainder = <ChatMessage>[];

    for (var start = 0;
        start < olderMessages.length;
        start += recentMessageCount) {
      final end = start + recentMessageCount;
      if (end > olderMessages.length) {
        rawRemainder.addAll(olderMessages.sublist(start));
        break;
      }

      final key = _rangeKey(start, end - 1);
      var summary = summaries[key];
      if (summary == null) {
        final content = await summarize(
          _formatBlock(olderMessages.sublist(start, end)),
        );
        if (content == null || content.trim().isEmpty) {
          rawRemainder.addAll(olderMessages.sublist(start, end));
          continue;
        }
        summary = AiConversationSummary(
          startSequence: start,
          endSequence: end - 1,
          content: content.trim(),
        );
        await AiHistoryStore.upsertSummary(
          conversationId: conversationId,
          startSequence: summary.startSequence,
          endSequence: summary.endSequence,
          content: summary.content,
        );
      }
      promptMessages.add(
        ChatMessage.system(
          'Conversation memory (messages ${summary.startSequence + 1}-'
          '${summary.endSequence + 1}):\n${summary.content}',
        ),
      );
    }

    promptMessages
      ..addAll(rawRemainder)
      ..addAll(recentMessages)
      ..add(currentMessage);
    return promptMessages;
  }

  String _formatBlock(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final role = message is HumanChatMessage ? 'User' : 'Assistant';
      final content = message is AIChatMessage
          ? reasoningContentToPlainText(message.content)
          : message.contentAsString;
      buffer.writeln('$role: ${content.trim()}');
    }
    return buffer.toString().trim();
  }

  String _rangeKey(int start, int end) => '$start:$end';
}
