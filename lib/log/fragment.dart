import 'package:logging/logging.dart';

import '../bootstrap/application_context.dart';
import '../util/date.dart';
import '../util/string.dart';

/// 日志片段
class LogFragment {
  /// Log level
  final Level level;

  /// Message to print
  final String message;

  /// StackTrace to find code quickly in error log
  final String stackTrace;

  /// Logger name, general is class name
  final String loggerName;

  /// Error message
  final String error;

  /// Active profile
  final String profile;

  /// Server port
  final int port;

  /// Request User ID
  final String userId;

  /// MicroService Trace ID
  final String traceId;

  LogFragment(this.level, this.message, this.loggerName,
      [this.error,
      this.stackTrace,
      this.profile,
      this.port,
      this.traceId,
      this.userId]);

  static LogFragment fromLogRecord(LogRecord record) {
    return LogFragment(
        record.level,
        record.message,
        record.loggerName,
        '${record.error ?? ''}',
        record.stackTrace?.toString() ?? '',
        ApplicationContext.instance['profile.active'] ?? 'default',
        ApplicationContext.instance['server.port'],
        record.zone['_rq_trace_id'],
        record.zone['_userid']);
  }

  @override
  String toString() {
    if (level == Level.OFF) {
      return message ?? '';
    }
    String result =
        '[${formatTime(DateTime.now())} :${profile ?? '--'}:${port ?? '--'}:] [U:${userId ?? ''} T:${traceId ?? ''}] [${level.name}] $loggerName: $message';
    if (isNotEmpty(error)) {
      result += '\n';
      result += '${error}\n';
      result += '${stackTrace}';
    }
    return result;
  }
}
