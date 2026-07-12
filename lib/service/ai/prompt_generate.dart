import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

class PromptTemplatePayload {
  const PromptTemplatePayload({
    required this.template,
    required this.variables,
    required this.identifier,
  });

  final ChatPromptTemplate template;
  final Map<String, dynamic> variables;
  final AiPrompts identifier;

  List<ChatMessage> buildMessages() {
    try {
      return template.formatPrompt(variables).toChatMessages();
    } catch (e) {
      Prefs().deleteAiPrompt(identifier);
      final prompt = Prefs().getAiPrompt(identifier);
      final normalized = _normalizePrompt(prompt);
      final template = ChatPromptTemplate.fromPromptMessages([
        HumanChatMessagePromptTemplate.fromTemplate(normalized),
      ]);
      return template.formatPrompt(variables).toChatMessages();
    }
  }

  String buildString() {
    return buildMessages().last.contentAsString;
  }
}

PromptTemplatePayload generatePromptTest() {
  final prompt = Prefs().getAiPrompt(AiPrompts.test);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  final currentLocale = Prefs().locale?.languageCode ?? Platform.localeName;
  return PromptTemplatePayload(
    template: template,
    variables: {'language_locale': currentLocale},
    identifier: AiPrompts.test,
  );
}

PromptTemplatePayload generatePromptSummaryTheChapter() {
  final prompt = Prefs().getAiPrompt(AiPrompts.summaryTheChapter);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {},
    identifier: AiPrompts.summaryTheChapter,
  );
}

PromptTemplatePayload generatePromptSummaryTheBook() {
  final prompt = Prefs().getAiPrompt(AiPrompts.summaryTheBook);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {},
    identifier: AiPrompts.summaryTheBook,
  );
}

PromptTemplatePayload generatePromptMindmap() {
  final prompt = Prefs().getAiPrompt(AiPrompts.mindmap);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {},
    identifier: AiPrompts.mindmap,
  );
}

PromptTemplatePayload generatePromptSummaryThePreviousContent(
    String previousContent) {
  final prompt = Prefs().getAiPrompt(AiPrompts.summaryThePreviousContent);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {
      'previous_content': previousContent.trim(),
    },
    identifier: AiPrompts.summaryThePreviousContent,
  );
}

PromptTemplatePayload generatePromptTranslate(
    String text, String toLocale, String fromLocale,
    {String? contextText}) {
  final prompt = Prefs().getAiPrompt(AiPrompts.translate);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {
      'text': text.trim(),
      'to_locale': toLocale,
      'from_locale': fromLocale,
      'contextText': (contextText ?? '').trim(),
    },
    identifier: AiPrompts.translate,
  );
}

PromptTemplatePayload generatePromptFullTextTranslate(
    String text, String toLocale, String fromLocale) {
  final prompt = Prefs().getAiPrompt(AiPrompts.fullTextTranslate);
  final normalized = _normalizePrompt(prompt);
  final template = ChatPromptTemplate.fromPromptMessages([
    HumanChatMessagePromptTemplate.fromTemplate(normalized),
  ]);
  return PromptTemplatePayload(
    template: template,
    variables: {
      'text': text.trim(),
      'to_locale': toLocale,
      'from_locale': fromLocale,
    },
    identifier: AiPrompts.fullTextTranslate,
  );
}

String generatePromptWithHighlights({
  required Book book,
  required List<BookNote> highlights,
  String? instruction,
}) {
  final buffer = StringBuffer(
      'The following are selected highlights from "${book.title}":');
  for (var index = 0; index < highlights.length; index++) {
    final highlight = highlights[index];
    buffer.writeln('\n\n${index + 1}. ${highlight.content.trim()}');
    if (highlight.chapter.trim().isNotEmpty) {
      buffer.writeln('Chapter: ${highlight.chapter.trim()}');
    }
    if (highlight.readerNote?.trim().isNotEmpty ?? false) {
      buffer.writeln('My note: ${highlight.readerNote!.trim()}');
    }
  }

  final trimmedInstruction = instruction?.trim();
  if (trimmedInstruction != null && trimmedInstruction.isNotEmpty) {
    buffer.writeln('\n\n$trimmedInstruction');
  }
  return buffer.toString();
}

String _normalizePrompt(String template) {
  return template.replaceAll('{{', '{').replaceAll('}}', '}');
}
