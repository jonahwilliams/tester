// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer';
import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// The test runner manages the lifecycle of the platform under test.
abstract class TestRunner {
  /// Start the test runner, returning the test isolate.
  ///
  /// [entrypoint] should be the generated entrypoint file for all
  /// bundled tests.
  ///
  /// [onExit] is invoked if the process exits before [dispose] is called.
  ///
  /// Throws a [StateError] if this method is called multiple times on
  /// the same instance.
  FutureOr<RunnerStartResult> start(Uri entrypoint, void Function() onExit);

  /// Perform cleanup necessary to tear down the test runner.
  ///
  /// Throws a [StateError] if this method is called multiple times on the same
  /// instance, or if it is called before [start].
  FutureOr<void> dispose();
}

/// The result of starting a [TestRunner].
class RunnerStartResult {
  const RunnerStartResult({
    @required this.serviceUri,
    @required this.isolateName,
  });

  /// The URI of the VM Service to connect to.
  final Uri serviceUri;

  /// A unique name for the isolate.
  final String isolateName;
}

/// A test runner which executes code on the Dart VM.
class VmTestRunner implements TestRunner {
  /// Create a new [VmTestRunner].s
  VmTestRunner();

  Isolate _isolate;
  var _disposed = false;

  @override
  Future<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    if (_isolate != null) {
      throw StateError('VmTestRunner already started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    var serviceInfo = await Service.getInfo();
    if (serviceInfo.serverUri == null) {
      throw StateError('Ensure tester is run with --observe');
    }
    var uniqueId = Uuid().v4();
    _isolate = await Isolate.spawnUri(
      entrypoint,
      [],
      null,
      debugName: uniqueId,
    );
    return RunnerStartResult(
      isolateName: uniqueId,
      serviceUri: serviceInfo.serverUri,
    );
  }

  @override
  void dispose() {
    if (_isolate == null) {
      throw StateError('VmTestRunner has not been started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _disposed = true;
    _isolate.kill();
  }
}
