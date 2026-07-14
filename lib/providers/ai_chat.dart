import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/conversation_memory.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  static const ConversationMemory _conversationMemory = ConversationMemory();
  String? _currentSessionId;
  AiChatHistoryEntry? _currentConversation;

  @override
  FutureOr<List<ChatMessage>> build() async {
    _currentSessionId = null;
    _currentConversation = null;
    return List<ChatMessage>.empty();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    state = AsyncData(history);
  }

  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate, {
    Book? book,
  }) async* {
    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = widgetRef.read(aiHistoryProvider.notifier);
    final initialHistoryState = widgetRef
        .read(aiHistoryProvider)
        .maybeWhen(data: (value) => value, orElse: () => const []);
    AiChatHistoryEntry? entry;
    for (final item in initialHistoryState) {
      if (item.id == sessionId) {
        entry = item;
        break;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final originalEntry = entry ?? _currentConversation;
    final boundBook = await _resolveBoundBook(originalEntry, book);

    List<ChatMessage> messages = [
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ];

    state = AsyncData(messages);

    List<ChatMessage> updatedMessages = [
      ...messages,
      ChatMessage.ai(''),
    ];

    final draftEntry = (originalEntry ??
            AiHistoryStore.createEntry(
              serviceId: serviceId,
              model: model,
              book: boundBook,
            ))
        .copyWith(
      messages: List<ChatMessage>.from(updatedMessages),
      updatedAt: now,
      completed: false,
      model: model,
    );

    await historyNotifier.upsert(draftEntry);
    _currentSessionId = draftEntry.id;
    _currentConversation = draftEntry;

    yield updatedMessages;

    String assistantResponse = "";
    try {
      final requestMessages = await _conversationMemory.buildPromptMessages(
        conversationId: draftEntry.id,
        messages: messages,
        summarize: _summarizeConversationBlock,
      );
      await for (final chunk in aiGenerateStream(
        requestMessages,
        regenerate: isRegenerate,
        useAgent: true,
        ref: widgetRef,
        conversation: _buildConversationContext(widgetRef, boundBook),
      )) {
        assistantResponse = chunk;

        final updatedMessagesWithResponse =
            List<ChatMessage>.from(updatedMessages);
        updatedMessagesWithResponse[updatedMessagesWithResponse.length - 1] =
            assistantMessageFromDisplayContent(assistantResponse);

        yield updatedMessagesWithResponse;

        state = AsyncData(updatedMessagesWithResponse);
      }
      final completedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: true,
        model: model,
      );
      await historyNotifier.upsert(completedEntry);
      _currentConversation = completedEntry;
    } catch (_) {
      final failedEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? updatedMessages),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: false,
        model: model,
      );
      await historyNotifier.upsert(failedEntry);
      _currentConversation = failedEntry;
      rethrow;
    }
  }

  void clear() {
    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _currentConversation = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    _currentSessionId = entry.id;
    _currentConversation = entry;
    state = AsyncData(List<ChatMessage>.from(entry.messages));
  }

  String? get currentSessionId => _currentSessionId;

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<Book?> _resolveBoundBook(
    AiChatHistoryEntry? entry,
    Book? requestedBook,
  ) async {
    final bookId = entry?.bookId;
    if (bookId == null) return requestedBook;
    if (requestedBook?.id == bookId) return requestedBook;
    try {
      return await bookDao.selectBookById(bookId);
    } on StateError {
      return null;
    }
  }

  AiConversationContext _buildConversationContext(
    WidgetRef ref,
    Book? book,
  ) {
    final reading = ref.read(currentReadingProvider);
    final isBoundBookOpen =
        book != null && reading.isReading && reading.book?.id == book.id;
    return AiConversationContext(
      book: book,
      readingState: isBoundBookOpen ? reading : null,
      chapterContentHandlers:
          isBoundBookOpen ? ref.read(chapterContentBridgeProvider) : null,
      tocItems: isBoundBookOpen ? ref.read(bookTocProvider) : const [],
    );
  }

  Future<String?> _summarizeConversationBlock(String block) async {
    var response = '';
    await for (final chunk in aiGenerateStream(
      [
        ChatMessage.humanText(
          '''Create compact durable memory for this conversation block.

Preserve user goals, preferences, constraints, decisions, unresolved questions, facts, and book-specific context. Do not include hidden reasoning, tool-call syntax, or transcript chatter. Write concise factual memory in the conversation's language.

Conversation block:
$block''',
        ),
      ],
      regenerate: false,
    )) {
      response = chunk;
    }
    if (response.trim().isEmpty || response.startsWith('Error:')) {
      return null;
    }
    return response;
  }
}
