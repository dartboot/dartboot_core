import 'package:logging/logging.dart';

/// 定义的LEVEL
const Level DEBUG = Level('DEBUG', 700);
const Level INFO = Level.INFO;
const Level WARNING = Level('WARNING', 900);
const Level ERROR = Level('ERROR', 1000);

/// 定制的日志类
///
/// usage:
/// ```
/// Log log = Log('debugName');
/// log.debug('Description here');
/// ```
///
/// @author luodongseu
class Log {
  /// 使用Logger对象打印
  Logger _logger;

  Log(String name) {
    _logger = Logger(name);
  }

  /// 设置root的日志level
  static void set rootLevel(Level l) => Logger.root.level = l;

  /// Log message at level [DEBUG].
  void debug(message, [Object error, StackTrace stackTrace]) =>
      _logger.log(DEBUG, message, error, stackTrace);

  /// Log message at level [INFO].
  void info(message, [Object error, StackTrace stackTrace]) =>
      _logger.log(INFO, message, error, stackTrace);

  /// Log message at level [WARNING].
  void warning(message, [Object error, StackTrace stackTrace]) =>
      _logger.log(WARNING, message, error, stackTrace);

  /// Log message at level [ERROR].
  void error(message, [Object error, StackTrace stackTrace]) =>
      _logger.log(ERROR, message, error, stackTrace ?? StackTrace.current);
}
