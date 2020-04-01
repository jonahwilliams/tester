// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:process/process.dart';

/// The test runner manages the lifecycle of the platform under test.
abstract class TestRunner {
  /// Start the test runner, returning the VM service URL.
  ///
  /// [entrypoint] should be the generated entrypoint file for all
  /// bundled tests.
  ///
  /// [onExit] is invoked if the process exits before [dispose] is called.
  ///
  /// Throws a [StateError] if this method is called multiple times on
  /// the same instance.
  FutureOr<Uri> start(String entrypoint, void Function() onExit);

  /// Perform cleanup necessary to tear down the test runner.
  ///
  /// Throws a [StateError] if this method is called multiple times on the same
  /// instance, or if it is called before [start].
  FutureOr<void> dispose();
}

/// A test runner which executes code on the Dart VM.
class VmTestRunner implements TestRunner {
  /// Create a new [VmTestRunner].
  ///
  /// Requires the [dartSdkPath], the file path to the dart SDK root.
  VmTestRunner({
    @required String dartSdkPath,
    @required ProcessManager processManager,
    @required FileSystem fileSystem,
  })  : _dartSdkPath = dartSdkPath,
        _processManager = processManager,
        _fileSystem = fileSystem;

  static final _serviceRegex = RegExp(RegExp.escape('Observatory') +
      r' listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)');

  final String _dartSdkPath;
  final ProcessManager _processManager;
  final FileSystem _fileSystem;

  Process _process;
  var _disposed = false;

  @override
  Future<Uri> start(String entrypoint, void Function() onExit) async {
    if (_process != null) {
      throw StateError('VmTestRunner already started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _process = await _processManager.start(<String>[
      _fileSystem.path.join(_dartSdkPath, 'bin', 'dart'),
      '--enable-vm-service',
      '--enable-asserts',
      entrypoint,
    ]);
    unawaited(_process.exitCode.whenComplete(() {
      if (!_disposed) {
        onExit();
      }
    }));

    // TODO: replace this with the VM service write file to path logic.
    var completer = Completer<Uri>();
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      var match = _serviceRegex.firstMatch(line);
      if (match == null) {
        return;
      }
      completer.complete(Uri.parse(match[1]));
    });
    return completer.future;
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
