// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:meta/meta.dart';

import 'compiler.dart';
import 'config.dart';
import 'isolate.dart';

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

  /// Recompile the tests and run all.
  Future<void> rerun() async {
    var result = await _compiler.recompile();
    if (result != null) {
      await _testIsolate.reload(result);
    }
    await for (var testResult in _testIsolate.runAllTests()) {
      var humanFileName = _fileSystem.path.relative(
        Uri.parse(testResult.testFile).toFilePath(),
        from: _config.workspacePath,
      );
      // Pass
      if (testResult.passed) {
        print('PASS    $humanFileName/${testResult.testName}');
        continue;
      }
      // Fail
      if (!testResult.passed && !testResult.timeout) {
        print('FAIL    $humanFileName/${testResult.testName}');
        print(testResult.errorMessage);
        print(testResult.stackTrace);
        continue;
      }
      // Timeout.
       print('TIMEOUT    $humanFileName/${testResult.testName}');
    }
  }

  void dispose() { }
}
