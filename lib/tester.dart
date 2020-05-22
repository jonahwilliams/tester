// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import 'src/compiler.dart';
import 'src/config.dart';
import 'src/isolate.dart';
import 'src/runner.dart';

void runApplication({
  @required bool batchMode,
  @required Config config,
}) async {
  var runners = <TestRunner>[];
  var compiler = Compiler(
    config: config,
    compilerMode: config.targetPlatform,
  );
  var result = await compiler.start();
  if (result == null) {
    return;
  }

  // Step 3. Load test isolate.
  TestRunner testRunner;
  switch (config.targetPlatform) {
    case TargetPlatform.dart:
      testRunner = VmTestRunner(
        dartExecutable: config.dartPath,
      );
      break;
    case TargetPlatform.flutter:
      testRunner = FlutterTestRunner(
        flutterTesterPath: config.flutterTesterPath,
      );
      break;
    case TargetPlatform.web:
      throw UnsupportedError('web is not yet supported');
      break;
    case TargetPlatform.flutterWeb:
      throw UnsupportedError('flutterWeb is not yet supported');
      break;
  }
  runners.add(testRunner);
  var testIsolate = TestIsolate(testRunner: testRunner);
  try {
    await testIsolate.start(result, () {});
  } on Exception catch (err) {
    print(err);
    testRunner.dispose();
    exit(1);
  }

  await for (var testResult in testIsolate.runAllTests()) {
    var humanFileName = path.relative(
      Uri.parse(testResult.testFile).toFilePath(),
      from: config.workspacePath,
    );
    if (testResult.passed == true) {
      print('PASS    $humanFileName/${testResult.testName}');
      continue;
    }
    if (!testResult.passed && !testResult.timeout) {
      exitCode = 1;
      print('FAIL    $humanFileName/${testResult.testName}');
      print(testResult.errorMessage);
      print(testResult.stackTrace);
      continue;
    }
    print('TIMEOUT    $humanFileName/${testResult.testName}');
    exitCode = 1;
  }
  exit(exitCode);
}
