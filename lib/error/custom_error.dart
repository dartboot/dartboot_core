/**
 * Error thrown by the runtime system when an custom fails.
 *
 * @author luodongseu
 */
class CustomError extends Error {
  /** Message describing the error. */
  final Object message;

  final Error e;

  CustomError([this.message, this.e]);

  String toString() => '${message ?? 'Unknown error'} ${e ?? ''}';
}
