import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum AiConversationScope { book, global }

class AiConversationSummary {
  const AiConversationSummary({
    required this.startSequence,
    required this.endSequence,
    required this.content,
  });

  final int startSequence;
  final int endSequence;
  final String content;
}

class AiChatHistoryEntry {
  const AiChatHistoryEntry({
    required this.id,
    required this.serviceId,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.completed,
    required this.scope,
    this.bookId,
    this.bookMd5,
    this.bookTitleSnapshot,
  });

  final String id;
  final String serviceId;
  final String model;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;
  final bool completed;
  final AiConversationScope scope;
  final int? bookId;
  final String? bookMd5;
  final String? bookTitleSnapshot;

  AiChatHistoryEntry copyWith({
    List<ChatMessage>? messages,
    int? updatedAt,
    bool? completed,
    String? model,
  }) {
    return AiChatHistoryEntry(
      id: id,
      serviceId: serviceId,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      completed: completed ?? this.completed,
      scope: scope,
      bookId: bookId,
      bookMd5: bookMd5,
      bookTitleSnapshot: bookTitleSnapshot,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceId': serviceId,
      'model': model,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completed': completed,
      'messages': messages.map((m) => m.toMap()).toList(growable: false),
      'scope': scope.name,
      'bookId': bookId,
      'bookMd5': bookMd5,
      'bookTitleSnapshot': bookTitleSnapshot,
    };
  }

  factory AiChatHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(ChatMessage.fromMap(item));
        } else if (item is Map) {
          messages.add(ChatMessage.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ));
        }
      }
    }

    return AiChatHistoryEntry(
      id: json['id']?.toString() ?? '',
      serviceId: json['serviceId']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      completed: json['completed'] == true,
      messages: messages,
      scope: json['scope'] == AiConversationScope.book.name
          ? AiConversationScope.book
          : AiConversationScope.global,
      bookId: json['bookId'] is int ? json['bookId'] as int : null,
      bookMd5: json['bookMd5']?.toString(),
      bookTitleSnapshot: json['bookTitleSnapshot']?.toString(),
    );
  }
}

class AiHistoryStore {
  static const String historyFileName = 'ai_history.json';

  static Future<List<AiChatHistoryEntry>> readHistory() async {
    final database = await DBHelper().database;
    await _migrateLegacyCache(database);
    final rows = await database.query(
      'tb_ai_conversations',
      orderBy: 'updated_at DESC',
    );
    return Future.wait(rows.map((row) => _entryFromRow(database, row)));
  }

  static Future<void> upsertEntry(AiChatHistoryEntry entry) async {
    final database = await DBHelper().database;
    await _migrateLegacyCache(database);
    await database.transaction((transaction) async {
      final values = _conversationValues(entry);
      final updated = await transaction.update(
        'tb_ai_conversations',
        values,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (updated == 0) {
        await transaction.insert('tb_ai_conversations', values);
      }
      await transaction.delete(
        'tb_ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [entry.id],
      );
      for (var index = 0; index < entry.messages.length; index++) {
        await transaction.insert('tb_ai_messages', {
          'id': const Uuid().v4(),
          'conversation_id': entry.id,
          'sequence': index,
          'message_json': jsonEncode(entry.messages[index].toMap()),
          'created_at': entry.updatedAt,
        });
      }
    });
  }

  static Future<void> removeEntry(String id) async {
    final database = await DBHelper().database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'tb_ai_messages',
        where: 'conversation_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'tb_ai_conversation_summaries',
        where: 'conversation_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'tb_ai_conversations',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  static Future<void> clear({AiConversationScope? scope, int? bookId}) async {
    final database = await DBHelper().database;
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (scope != null) {
      whereParts.add('scope = ?');
      whereArgs.add(scope.name);
    }
    if (bookId != null) {
      whereParts.add('book_id = ?');
      whereArgs.add(bookId);
    }
    final where = whereParts.isEmpty ? null : whereParts.join(' AND ');
    await database.transaction((transaction) async {
      if (where == null) {
        await transaction.delete('tb_ai_conversation_summaries');
        await transaction.delete('tb_ai_messages');
        await transaction.delete('tb_ai_conversations');
        return;
      }
      final conversations = await transaction.query(
        'tb_ai_conversations',
        columns: ['id'],
        where: where,
        whereArgs: whereArgs,
      );
      for (final conversation in conversations) {
        await transaction.delete(
          'tb_ai_conversation_summaries',
          where: 'conversation_id = ?',
          whereArgs: [conversation['id']],
        );
        await transaction.delete(
          'tb_ai_messages',
          where: 'conversation_id = ?',
          whereArgs: [conversation['id']],
        );
      }
      await transaction.delete(
        'tb_ai_conversations',
        where: where,
        whereArgs: whereArgs,
      );
    });
  }

  static Future<List<AiConversationSummary>> readSummaries(
    String conversationId,
  ) async {
    final database = await DBHelper().database;
    final rows = await database.query(
      'tb_ai_conversation_summaries',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'start_sequence ASC',
    );
    return rows
        .map(
          (row) => AiConversationSummary(
            startSequence: row['start_sequence'] as int,
            endSequence: row['end_sequence'] as int,
            content: row['summary'] as String,
          ),
        )
        .toList(growable: false);
  }

  static Future<void> upsertSummary({
    required String conversationId,
    required int startSequence,
    required int endSequence,
    required String content,
  }) async {
    final database = await DBHelper().database;
    await database.insert(
      'tb_ai_conversation_summaries',
      {
        'conversation_id': conversationId,
        'start_sequence': startSequence,
        'end_sequence': endSequence,
        'summary': content,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static AiChatHistoryEntry createEntry({
    required String serviceId,
    required String model,
    Book? book,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AiChatHistoryEntry(
      id: const Uuid().v4(),
      serviceId: serviceId,
      model: model,
      createdAt: now,
      updatedAt: now,
      messages: const [],
      completed: false,
      scope:
          book == null ? AiConversationScope.global : AiConversationScope.book,
      bookId: book?.id,
      bookMd5: book?.md5,
      bookTitleSnapshot: book?.title,
    );
  }

  static Map<String, Object?> _conversationValues(AiChatHistoryEntry entry) => {
        'id': entry.id,
        'scope': entry.scope.name,
        'book_id': entry.bookId,
        'book_md5': entry.bookMd5,
        'book_title_snapshot': entry.bookTitleSnapshot,
        'service_id': entry.serviceId,
        'model': entry.model,
        'created_at': entry.createdAt,
        'updated_at': entry.updatedAt,
        'completed': entry.completed ? 1 : 0,
      };

  static Future<AiChatHistoryEntry> _entryFromRow(
    DatabaseExecutor database,
    Map<String, Object?> row,
  ) async {
    final messagesRows = await database.query(
      'tb_ai_messages',
      where: 'conversation_id = ?',
      whereArgs: [row['id']],
      orderBy: 'sequence ASC',
    );
    final messages = messagesRows.map((messageRow) {
      final raw = jsonDecode(messageRow['message_json'] as String);
      return ChatMessage.fromMap(Map<String, dynamic>.from(raw as Map));
    }).toList(growable: false);
    return AiChatHistoryEntry(
      id: row['id'] as String,
      serviceId: row['service_id'] as String? ?? '',
      model: row['model'] as String? ?? '',
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      messages: messages,
      completed: (row['completed'] as int? ?? 0) == 1,
      scope: row['scope'] == AiConversationScope.book.name
          ? AiConversationScope.book
          : AiConversationScope.global,
      bookId: row['book_id'] as int?,
      bookMd5: row['book_md5'] as String?,
      bookTitleSnapshot: row['book_title_snapshot'] as String?,
    );
  }

  static Future<void> _migrateLegacyCache(Database database) async {
    final migrated = await database.query(
      'tb_ai_conversations',
      limit: 1,
    );
    if (migrated.isNotEmpty) return;
    final file = await _resolveFile();
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      await database.transaction((transaction) async {
        for (final item in decoded.whereType<Map>()) {
          final legacy = AiChatHistoryEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          final entry = AiChatHistoryEntry(
            id: const Uuid().v4(),
            serviceId: legacy.serviceId,
            model: legacy.model,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            messages: legacy.messages,
            completed: legacy.completed,
            scope: AiConversationScope.global,
          );
          await transaction.insert(
              'tb_ai_conversations', _conversationValues(entry));
          for (var index = 0; index < entry.messages.length; index++) {
            await transaction.insert('tb_ai_messages', {
              'id': const Uuid().v4(),
              'conversation_id': entry.id,
              'sequence': index,
              'message_json': jsonEncode(entry.messages[index].toMap()),
              'created_at': entry.updatedAt,
            });
          }
        }
      });
      await file.delete();
    } catch (_) {
      // Preserve unreadable legacy data rather than deleting user history.
    }
  }

  static Future<File> _resolveFile() async {
    final cacheDir = await getAnxCacheDir();
    return File('${cacheDir.path}/$historyFileName');
  }
}
