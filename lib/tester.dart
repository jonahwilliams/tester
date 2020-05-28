// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:meta/meta.dart';

import 'src/progress.dart';
import 'src/test_info.dart';
import 'src/compiler.dart';
import 'src/config.dart';
import 'src/isolate.dart';
import 'src/resident.dart';
import 'src/runner.dart';
import 'src/web_runner.dart';
import 'src/writer.dart';

void runApplication({
  @required bool verbose,
  @required bool batchMode,
  @required bool ci,
  @required Config config,
}) async {
  var progress = Progress(ci: ci);
  progress.start('Loading the test isolate');
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
  TestIsolate testIsolate;

  switch (config.targetPlatform) {
    case TargetPlatform.dart:
      var testRunner = VmTestRunner(
        dartExecutable: config.dartPath,
      );
      testIsolate = VmTestIsolate(testRunner: testRunner);
      break;
    case TargetPlatform.flutter:
      var testRunner = FlutterTestRunner(
        flutterTesterPath: config.flutterTesterPath,
      );
      testIsolate = VmTestIsolate(testRunner: testRunner);
      break;
    case TargetPlatform.web:
      var testRunner = ChromeTestRunner(
        dartSdkFile: File(config.webDartSdk),
        dartSdkSourcemap: File(config.webDartSdkSourcemaps),
        stackTraceMapper: File(config.stackTraceMapper),
        requireJS: File(config.requireJS),
        config: config,
      );
      testIsolate = WebTestIsolate(testRunner: testRunner);
      break;
    case TargetPlatform.flutterWeb:
      var testRunner = ChromeTestRunner(
        dartSdkFile: File(config.flutterWebDartSdk),
        dartSdkSourcemap: File(config.flutterWebDartSdkSourcemaps),
        stackTraceMapper: File(config.stackTraceMapper),
        requireJS: File(config.requireJS),
        config: config,
      );
      testIsolate = WebTestIsolate(testRunner: testRunner);
      break;
  }
  try {
    await testIsolate.start(result, () {});
  } on Exception catch (err, st) {
    print(err);
    print(st);
    testIsolate.dispose();
    exit(1);
  }
  var writer = TestWriter(
    projectRoot: config.packageRootPath,
    verbose: verbose,
    ci: ci,
  );
  progress.stop();
  if (batchMode) {
    writer.writeHeader();
    for (var testFileUri in testInformation.keys) {
      for (var testInfo in testInformation[testFileUri]) {
        var testResult = await testIsolate.runTest(testInfo);
        writer.writeTest(testResult, testInfo);
      }
    }
    writer.writeSummary();
    testIsolate.dispose();
    exit(writer.exitCode);
  }

  var resident = Resident(
    config: config,
    compiler: compiler,
    testIsolate: testIsolate,
    writer: writer,
  );
  print('READY');
  await resident.start();
}
