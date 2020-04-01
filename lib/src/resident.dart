// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dart_console/dart_console.dart';
import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:tester/src/compiler.dart';
import 'package:tester/src/config.dart';
import 'package:tester/src/isolate.dart';

/// A resident process which routes commands to the appropriate action.
///
/// This only supports a simple workflow of recompiling, reloading, and
/// rerunning.
class Resident {
  Resident({
    @required Compiler compiler,
    @required TestIsolate testIsolate,
    @required FileSystem fileSystem,
    @required Config config,
  })  : _compiler = compiler,
        _config = config,
        _testIsolate = testIsolate,
        _fileSystem = fileSystem;

  final Compiler _compiler;
  final TestIsolate _testIsolate;
  final FileSystem _fileSystem;
  final Config _config;
  final _console = Console();

  /// Recompile the tests and run all.
  Future<void> rerun() async {
    var result = await _compiler.recompile();
    if (result == null) {
      return;
    }
    await _testIsolate.reload(result);
    // TODO: only erase output from the last test.
    _console.clearScreen();
    await for (var testResult in _testIsolate.runAllTests()) {
      var humanFileName = _fileSystem.path.relative(
        Uri.parse(testResult.testFile).toFilePath(),
        from: _config.workspacePath,
      );
      // Pass
      if (testResult.passed) {
        _console.setBackgroundColor(ConsoleColor.brightGreen);
        _console.write('PASS');
        _console.resetColorAttributes();
        _console.writeLine(
            '    $humanFileName/${testResult.testName}');
        continue;
      }
      // Fail
      if (!testResult.passed && !testResult.timeout) {
        _console.setBackgroundColor(ConsoleColor.brightRed);
        _console.write('FAIL');
        _console.resetColorAttributes();
        _console.writeLine(
            '    $humanFileName/${testResult.testName}');
        _console.writeLine(testResult.errorMessage);
        _console.writeLine(testResult.stackTrace);
        continue;
      }
      // Timeout.
      _console.setBackgroundColor(ConsoleColor.brightYellow);
      _console.write('TIMEOUT');
      _console.resetColorAttributes();
      _console.writeLine(
          '    $humanFileName/${testResult.testName}');
    }
  }

  void dispose() {
    _console.resetColorAttributes();
  }
}
