// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A load-balancing runner pool.
import 'dart:async';
import 'dart:math' as Math;

import 'package:dio/dio.dart';

import 'runner.dart';

/// A pool of runners, ordered by load.
///
/// Keeps a pool of runners,
/// and allows running function through the runner with the lowest current load.
class LoadBalancer implements Runner {
  // A heap-based priority queue of entries, prioritized by `load`.
  // Each entry has its own entry in the queue, for faster update.
  List<_LoadBalancerEntry> _queue;

  // The number of entries currently in the queue.
  int _length;

  // Whether [stop] has been called.
  Future<void> _stopFuture;

  /// Create a load balancer backed by the [Runner]s of [runners].
  LoadBalancer(Iterable<Runner> runners) : this._(_createEntries(runners));

  LoadBalancer._(List<_LoadBalancerEntry> entries)
      : _queue = entries,
        _length = entries.length {
    for (var i = 0; i < _length; i++) {
      _queue[i].queueIndex = i;
    }
  }

  /// The number of runners currently in the pool.
  int get length => _length;

  /// Asynchronously create [size] runners and create a `LoadBalancer` of those.
  ///
  /// This is a helper function that makes it easy to create a `LoadBalancer`
  /// with asynchronously created runners, for example:
  /// ```dart
  /// var isolatePool = LoadBalancer.create(10, IsolateRunner.spawn);
  /// ```
  static Future<LoadBalancer> create(
      int size, Future<Runner> Function() createRunner) {
    return Future.wait(Iterable.generate(size, (_) => createRunner()),
        cleanUp: (Runner runner) {
      runner.close();
    }).then((runners) => LoadBalancer(runners));
  }

  static List<_LoadBalancerEntry> _createEntries(Iterable<Runner> runners) {
    var entries = runners.map((runner) => _LoadBalancerEntry(runner));
    return List<_LoadBalancerEntry>.from(entries, growable: false);
  }

  /// Execute the command in the currently least loaded isolate.
  ///
  /// The optional [load] parameter represents the load that the command
  /// is causing on the isolate where it runs.
  /// The number has no fixed meaning, but should be seen as relative to
  /// other commands run in the same load balancer.
  /// The `load` must not be negative.
  ///
  /// If [timeout] and [onTimeout] are provided, they are forwarded to
  /// the runner running the function, which will handle a timeout
  /// as normal. If the runners are running in other isolates, then
  /// the [onTimeout] function must be a constant function.
  @override
  Future<Response<R>> run<R>(String path,
      {data,
      Map<String, dynamic> queryParameters,
      CancelToken cancelToken,
      Options options,
      ProgressCallback onSendProgress,
      ProgressCallback onReceiveProgress}) {
    var entry = _random;
    return entry.run(
      this,
      path,
      queryParameters: queryParameters,
      options: options,
      onReceiveProgress: onReceiveProgress,
      cancelToken: cancelToken,
    );
  }

  Future<void> close() {
    if (_stopFuture != null) return _stopFuture;
    _stopFuture =
        MultiError.waitUnordered(_queue.take(_length).map((e) => e.close()))
            .then(ignore);
    // Remove all entries.
    for (var i = 0; i < _length; i++) {
      _queue[i].queueIndex = -1;
    }
    _queue = null;
    _length = 0;
    return _stopFuture;
  }

  _LoadBalancerEntry get _random {
    assert(_length > 0);
    return _queue[Math.Random.secure().nextInt(_length)];
  }

}

class _LoadBalancerEntry implements Comparable<_LoadBalancerEntry> {
  // The current load on the isolate.
  int load = 0;

  // The current index in the heap-queue.
  // Negative when the entry is not part of the queue.
  int queueIndex = -1;

  // The service used to send commands to the other isolate.
  Runner runner;

  _LoadBalancerEntry(Runner runner) : runner = runner;

  /// Whether the entry is still in the queue.
  bool get inQueue => queueIndex >= 0;

  Future<Response<R>> run<R>(LoadBalancer balancer, String path,
      {data,
      Map<String, dynamic> queryParameters,
      CancelToken cancelToken,
      Options options,
      ProgressCallback onSendProgress,
      ProgressCallback onReceiveProgress}) {
    return runner
        .run(path,
            data: data,
            queryParameters: queryParameters,
            options: options,
            onReceiveProgress: onReceiveProgress,
            onSendProgress: onSendProgress,
            cancelToken: cancelToken)
        .whenComplete(() {
//      balancer._decreaseLoad(this, load);
    });
  }

  Future close() => runner.close();

  @override
  int compareTo(_LoadBalancerEntry other) => load - other.load;
}

// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper functions for working with errors.
///
/// The [MultiError] class combines multiple errors into one object,
/// and the [MultiError.wait] function works like [Future.wait] except
/// that it returns all the errors.
class MultiError extends Error {
  // Limits the number of lines included from each error's error message.
  // A best-effort attempt is made at keeping below this number of lines
  // in the output.
  // If there are too many errors, they will all get at least one line.
  static const int _maxLines = 55;

  // Minimum number of lines in the toString for each error.
  static const int _minLinesPerError = 1;

  /// The actual errors.
  final List errors;

  /// Create a `MultiError` based on a list of errors.
  ///
  /// The errors represent errors of a number of individual operations.
  ///
  /// The list may contain `null` values, if the index of the error in the
  /// list is useful.
  MultiError(this.errors);

  /// Waits for all [futures] to complete, like [Future.wait].
  ///
  /// Where `Future.wait` only reports one error, even if multiple
  /// futures complete with errors, this function will complete
  /// with a [MultiError] if more than one future completes with an error.
  ///
  /// The order of values is not preserved (if that is needed, use
  /// [wait]).
  static Future<List<Object>> waitUnordered<T>(Iterable<Future<T>> futures,
      {void Function(T successResult) cleanUp}) {
    Completer<List<Object>> completer;
    var count = 0;
    var errors = 0;
    var values = 0;
    // Initialized to `new List(count)` when count is known.
    // Filled up with values on the left, errors on the right.
    // Order is not preserved.
    List<Object> results;
    void checkDone() {
      if (errors + values < count) return;
      if (errors == 0) {
        completer.complete(results);
        return;
      }
      var errorList = results.sublist(results.length - errors);
      completer.completeError(MultiError(errorList));
    }

    var handleValue = (T v) {
      // If this fails because [results] is null, there is a future
      // which breaks the Future API by completing immediately when
      // calling Future.then, probably by misusing a synchronous completer.
      results[values++] = v;
      if (errors > 0 && cleanUp != null) {
        Future.sync(() => cleanUp(v));
      }
      checkDone();
    };
    var handleError = (e, s) {
      if (errors == 0 && cleanUp != null) {
        for (var i = 0; i < values; i++) {
          var value = results[i];
          if (value != null) Future.sync(() => cleanUp(value));
        }
      }
      results[results.length - ++errors] = e;
      checkDone();
    };
    for (var future in futures) {
      count++;
      future.then(handleValue, onError: handleError);
    }
    if (count == 0) return Future.value(List(0));
    results = List(count);
    completer = Completer();
    return completer.future;
  }

  /// Waits for all [futures] to complete, like [Future.wait].
  ///
  /// Where `Future.wait` only reports one error, even if multiple
  /// futures complete with errors, this function will complete
  /// with a [MultiError] if more than one future completes with an error.
  ///
  /// The order of values is preserved, and if any error occurs, the
  /// [MultiError.errors] list will have errors in the corresponding slots,
  /// and `null` for non-errors.
  Future<List<Object>> wait<T>(Iterable<Future<T>> futures,
      {void Function(T successResult) cleanUp}) {
    Completer<List<Object>> completer;
    var count = 0;
    var hasError = false;
    var completed = 0;
    // Initialized to `new List(count)` when count is known.
    // Filled with values until the first error, then cleared
    // and filled with errors.
    List<Object> results;
    void checkDone() {
      completed++;
      if (completed < count) return;
      if (!hasError) {
        completer.complete(results);
        return;
      }
      completer.completeError(MultiError(results));
    }

    for (var future in futures) {
      var i = count;
      count++;
      future.then((v) {
        if (!hasError) {
          results[i] = v;
        } else if (cleanUp != null) {
          Future.sync(() => cleanUp(v));
        }
        checkDone();
      }, onError: (e, s) {
        if (!hasError) {
          if (cleanUp != null) {
            for (var i = 0; i < results.length; i++) {
              var result = results[i];
              if (result != null) Future.sync(() => cleanUp(result));
            }
          }
          results = List<Object>(count);
          hasError = true;
        }
        results[i] = e;
        checkDone();
      });
    }
    if (count == 0) return Future.value(List(0));
    results = List<T>(count);
    completer = Completer();
    return completer.future;
  }

  @override
  String toString() {
    var buffer = StringBuffer();
    buffer.write('Multiple Errors:\n');
    var linesPerError = _maxLines ~/ errors.length;
    if (linesPerError < _minLinesPerError) {
      linesPerError = _minLinesPerError;
    }

    for (var index = 0; index < errors.length; index++) {
      var error = errors[index];
      if (error == null) continue;
      var errorString = error.toString();
      var end = 0;
      for (var i = 0; i < linesPerError; i++) {
        end = errorString.indexOf('\n', end) + 1;
        if (end == 0) {
          end = errorString.length;
          break;
        }
      }
      buffer.write('#$index: ');
      buffer.write(errorString.substring(0, end));
      if (end < errorString.length) {
        buffer.write('...\n');
      }
    }
    return buffer.toString();
  }
}

// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Utility functions.
/// Ignore an argument.
///
/// Can be used to drop the result of a future like `future.then(ignore)`.
void ignore(_) {}

/// Create a single-element fixed-length list.
List<Object> list1(Object v1) => List(1)..[0] = v1;

/// Create a two-element fixed-length list.
List<Object> list2(Object v1, Object v2) => List(2)
  ..[0] = v1
  ..[1] = v2;

/// Create a three-element fixed-length list.
List<Object> list3(Object v1, Object v2, Object v3) => List(3)
  ..[0] = v1
  ..[1] = v2
  ..[2] = v3;

/// Create a four-element fixed-length list.
List<Object> list4(Object v1, Object v2, Object v3, Object v4) => List(4)
  ..[0] = v1
  ..[1] = v2
  ..[2] = v3
  ..[3] = v4;

/// Create a five-element fixed-length list.
List<Object> list5(Object v1, Object v2, Object v3, Object v4, Object v5) =>
    List(5)
      ..[0] = v1
      ..[1] = v2
      ..[2] = v3
      ..[3] = v4
      ..[4] = v5;
