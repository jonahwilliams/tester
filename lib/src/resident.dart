// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'compiler.dart';
import 'config.dart';
import 'isolate.dart';

/// A resident process which routes commands to the appropriate action.
///
/// This only supports a simple workflow of recompiling, reloading, and
/// rerunning.
class Resident {
  Resident({
    @required this.compiler,
    @required this.config,
    @required this.testIsolate,
  });

  final Compiler compiler;
  final TestIsolate testIsolate;
  final Config config;

  /// Recompile the tests and run all.
  Future<void> rerun() async {
    var result = await compiler.recompile();
    if (result != null) {
      await testIsolate.reload(result);
    }
    await for (var testResult in testIsolate.runAllTests()) {
      var humanFileName = path.relative(
        Uri.parse(testResult.testFile).toFilePath(),
        from: config.workspacePath,
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

  void dispose() {}
}
