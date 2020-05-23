// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:tester/src/test_info.dart';

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
  var infoProvider = TestInformationProvider();

  var testInformation = <Uri, List<TestInfo>>{};
  for (var testFileUri in config.tests) {
    testInformation[testFileUri] = infoProvider.collectTestInfo(testFileUri);
  }

  var result = await compiler.start(testInformation);
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
    case TargetPlatform.flutterWeb:
      testRunner = ChromeTestRunner();
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

  await for (var testResult in testIsolate.runAllTests(testInformation)) {
    var humanFileName = path.relative(
      testResult.testFileUri.toFilePath(),
      from: config.workspacePath,
    );
    var testInfo = testInformation[testResult.testFileUri]
      .firstWhere((info) => info.name == testResult.testName);
    if (testResult.passed == true) {
      print('PASS    $humanFileName/${testResult.testName}');
      continue;
    }
    if (!testResult.passed && !testResult.timeout) {
      exitCode = 1;
      print('FAIL    $humanFileName/${testResult.testName}');
      print('');
      if (testInfo.description.isNotEmpty) {
        print(testInfo.description);
      }
      print(testResult.errorMessage);
      print(testResult.stackTrace);
      continue;
    }
    print('TIMEOUT    $humanFileName/${testResult.testName}');
    exitCode = 1;
  }
  exit(exitCode);
}
