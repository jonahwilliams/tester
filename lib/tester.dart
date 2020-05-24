// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:tester/src/test_info.dart';

import 'src/compiler.dart';
import 'src/config.dart';
import 'src/isolate.dart';
import 'src/runner.dart';
import 'src/writer.dart';

void runApplication({
  @required bool verbose,
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

  var writer = TerminalTestWriter(
    projectRoot: config.packageRootPath,
    verbose: verbose,
  );
  writer.writeHeader();
  await for (var testResult in testIsolate.runAllTests(testInformation)) {
    var testInfo = testInformation[testResult.testFileUri]
        .firstWhere((info) => info.name == testResult.testName);
    writer.writeTest(testResult, testInfo);
  }
  writer.writeSummary();
  exit(writer.exitCode);
}
