import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'usage_parser.dart';

/// Claude repeats usage on streamed content blocks. Message IDs identify a
/// response globally, so clones and subagent copies must not be counted twice.
class ClaudeParser implements UsageParser {
  static const version = 1;
  String session = '', project = '';
  ClaudeParser([Json? saved]) {
    session = saved?['session'] as String? ?? '';
    project = saved?['project'] as String? ?? '';
  }
  @override
  Json get state => {
    'parserVersion': version,
    'parserKind': 'claude',
    'session': session,
    'project': project,
  };
  @override
  AccountSnapshot? get quota => null;
  @override
  UsageEvent? parse(String line) {
    if (!line.contains('"usage"') && !line.contains('"cwd"')) return null;
    Json j;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      j = Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    if (j['sessionId'] is String) session = j['sessionId'];
    if (j['cwd'] is String) project = j['cwd'];
    final message = j['message'];
    if (j['type'] != 'assistant' ||
        j['isApiErrorMessage'] == true ||
        message is! Map ||
        message['usage'] is! Map) {
      return null;
    }
    final at = DateTime.tryParse(j['timestamp']?.toString() ?? '');
    final model = message['model'];
    if (at == null || model is! String || model.startsWith('<')) return null;
    final usage = message['usage'] as Map;
    int count(dynamic value) =>
        value is num && value.isFinite && value >= 0 ? value.toInt() : 0;
    final cached = count(usage['cache_read_input_tokens']);
    final creation = count(usage['cache_creation_input_tokens']);
    final detail = usage['cache_creation'];
    final hour = detail is Map
        ? count(detail['ephemeral_1h_input_tokens']).clamp(0, creation)
        : 0;
    final tokens = Tokens(
      count(usage['input_tokens']) + cached + creation,
      cached,
      count(usage['output_tokens']),
      0,
      creation,
      hour,
    ).normalized;
    if (tokens.total == 0) return null;
    final id = message['id'] ?? j['requestId'] ?? j['uuid'];
    if (id is! String || id.isEmpty) return null;
    return UsageEvent(
      id: 'claude-${sha256.convert(utf8.encode(id))}',
      session: session.isEmpty ? id : session,
      project: project,
      model: model,
      at: at,
      tokens: tokens,
    );
  }
}
