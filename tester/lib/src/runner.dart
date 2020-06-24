// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';

/// The test runner manages the lifecycle of the platform under test.
abstract class TestRunner {
  /// Start the test runner, returning a [RunnerStartResult].
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

Future<String> _pollForServiceFile(File file) async {
  while (true) {
    if (file.existsSync()) {
      var result = file.readAsStringSync();
      file.deleteSync();
      return result;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
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
  /// Create a new [VmTestRunner].
  VmTestRunner({
    @required this.dartExecutable,
  });

  final String dartExecutable;

  Process _process;
  var _disposed = false;

  @override
  Future<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    if (_process != null) {
      throw StateError('VmTestRunner already started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    var uniqueFile = File(Object().hashCode.toString());
    if (uniqueFile.existsSync()) {
      uniqueFile.deleteSync();
    }
    _process = await Process.start(dartExecutable, <String>[
      '--enable-asserts',
      '--disable-dart-dev',
      '--enable-vm-service=0',
      '--write-service-info=${uniqueFile.path}',
      entrypoint.toString(),
    ]);
    unawaited(_process.exitCode.whenComplete(() {
      if (!_disposed) {
        onExit();
      }
    }));
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderr.writeln);

    var serviceContents = await _pollForServiceFile(uniqueFile);

    return RunnerStartResult(
      isolateName: '',
      serviceUri: Uri.parse(json.decode(serviceContents)['uri'] as String),
    );
  }

  @override
  void dispose() {
    if (_process == null) {
      throw StateError('VmTestRunner has not been started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _disposed = true;
    _process.kill();
  }
}

/// A tester runner that delegates to a flutter_tester process.
class FlutterTestRunner extends TestRunner {
  /// Create a new [FlutterTestRunner].
  FlutterTestRunner({
    @required this.flutterTesterPath,
  });

  final String flutterTesterPath;

  static final _serviceRegex = RegExp(RegExp.escape('Observatory') +
      r' listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)');

  Process _process;
  bool _disposed = false;

  @override
  FutureOr<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    var uniqueFile = File(Object().hashCode.toString());
    if (uniqueFile.existsSync()) {
      uniqueFile.deleteSync();
    }
    _process = await Process.start(flutterTesterPath, <String>[
      '--enable-vm-service=0',
      '--enable-checked-mode',
      '--verify-entry-points',
      '--enable-software-rendering',
      '--skia-deterministic-rendering',
      '--enable-dart-profiling',
      '--non-interactive',
      '--use-test-fonts',
      '--run-forever',
      entrypoint.toFilePath(),
    ], environment: <String, String>{
      'FLUTTER_TEST': 'true',
    });
    unawaited(_process.exitCode.whenComplete(() {
      if (!_disposed) {
        onExit();
      }
    }));
    var serviceInfo = Completer<Uri>();
    StreamSubscription subscription;
    subscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      var match = _serviceRegex.firstMatch(line);
      if (match == null) {
        return;
      }
      serviceInfo.complete(Uri.parse(match[1]));
      subscription.cancel();
    });
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(stderr.writeln);

    return RunnerStartResult(
        isolateName: '', serviceUri: await serviceInfo.future);
  }

  @override
  FutureOr<void> dispose() {
    if (_process == null) {
      throw StateError('VmTestRunner has not been started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _disposed = true;
    _process.kill();
  }
}
