// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:devtools_server/devtools_server.dart' as devtools_server;

import 'coverage.dart';
import 'test_info.dart';
import 'compiler.dart';
import 'config.dart';
import 'isolate.dart';
import 'resident.dart';
import 'runner.dart';
import 'web_runner.dart';
import 'writer.dart';

void runApplication({
  @required bool verbose,
  @required bool batchMode,
  @required bool ci,
  @required Config config,
  @required String coverageOutputPath,
  @required String appName,
  @required int timeout,
  @required int concurrency,
  @required List<String> enabledExperiments,
  @required bool soundNullSafety,
  @required bool debugger,
  @required bool testCompatMode,
  @required TargetPlatform targetPlatform,
  @required List<Uri> tests,
  @required String packagesRootPath,
  @required String workspacePath,
}) async {
  if (!batchMode || (coverageOutputPath != null || debugger)) {
    concurrency = 1;
  }
  var coverage = CoverageService();
  var compiler = Compiler(
    config: config,
    compilerMode: targetPlatform,
    timeout: debugger ? -1 : timeout,
    soundNullSafety: soundNullSafety,
    enabledExperiments: enabledExperiments,
    testCompatMode: testCompatMode,
    workspacePath: workspacePath,
    packagesRootPath: packagesRootPath,
  );
  var infoProvider = TestInformationProvider(
    config: config,
    testCompatMode: testCompatMode,
    packagesRootPath: packagesRootPath,
  );
  var testCount = 0;
  var testInformation = <Uri, List<TestInfo>>{};
  for (var testFileUri in tests) {
    var infos = infoProvider.collectTestInfo(testFileUri);
    testCount += infos.length;
    testInformation[testFileUri] = infos;
  }

  var result = await compiler.start(testInformation);
  if (result == null) {
    exit(1);
  }

  var testIsolates = <TestIsolate>[];
  var loadingIsolates = <Future<void>>[];
  for (var i = 0; i < concurrency; i++) {
    TestIsolate testIsolate;
    switch (targetPlatform) {
      case TargetPlatform.dart:
        // Use the flutter tester platform for VM tests to improve performance.
        // The set of supported libraries is almost the same, except for mirrors
        // which is not worth supporting.
        if (config.flutterTesterPath != null) {
          continue flutter;
        }
        var testRunner = VmTestRunner(
          dartExecutable: config.dartPath,
        );
        testIsolate = VmTestIsolate(testRunner: testRunner);
        break;
      flutter:
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
          packagesRootPath: packagesRootPath,
        );
        testIsolate = WebTestIsolate(testRunner: testRunner);
        break;
      case TargetPlatform.flutterWeb:
        var testRunner = ChromeTestRunner(
          dartSdkFile: File(config.flutterWebDartSdk),
          dartSdkSourcemap: File(config.flutterWebDartSdkSourcemaps),
          stackTraceMapper: File(config.stackTraceMapper),
          requireJS: File(config.requireJS),
          packagesRootPath: packagesRootPath,
          config: config,
        );
        testIsolate = WebTestIsolate(testRunner: testRunner);
        break;
    }
    loadingIsolates.add(testIsolate.start(result, () {}).then((_) {
      testIsolates.add(testIsolate);
    }, onError: (dynamic err, StackTrace st) {
      print(err);
      print(st);
      testIsolate.dispose();
      exit(1);
    }));
  }
  await Future.wait(loadingIsolates);

  var writer = TestWriter(
    projectRoot: packagesRootPath,
    verbose: verbose,
    ci: ci,
    testCount: testCount,
  );
  HttpServer devtoolServer;
  if (debugger) {
    devtoolServer = await devtools_server.serveDevTools(
      enableStdinCommands: false,
    );
    await devtools_server.launchDevTools(
      <String, dynamic>{
        'reuseWindows': true,
      },
      testIsolates.single.vmServiceAddress,
      'http://${devtoolServer.address.host}:${devtoolServer.port}',
      false, // headless mode,
      false, // machine mode
    );
  }

  if (batchMode) {
    writer.writeHeader();
    var workLists = <List<TestInfo>>[
      for (var i = 0; i < concurrency; i++) <TestInfo>[],
    ];
    var currentTarget = 0;
    void addAndSwitch(TestInfo testInfo) {
      workLists[currentTarget].add(testInfo);
      currentTarget += 1;
      currentTarget %= concurrency;
    }

    <TestInfo>[
      for (var testFileUri in testInformation.keys)
        for (var testInfo in testInformation[testFileUri]) testInfo
    ]
      ..shuffle()
      ..forEach(addAndSwitch);

    await Future.wait(<Future<void>>[
      for (var i = 0; i < concurrency; i++)
        (() async {
          var tests = workLists[i];
          for (var testInfo in tests) {
            var testResult = await testIsolates[i].runTest(testInfo, debugger);
            writer.writeTest(testResult, testInfo);
          }
        })()
    ]);

    writer.writeSummary();
    if (coverageOutputPath != null) {
      var packagesPath =
          const LocalFileSystem().path.join(packagesRootPath, '.packages');
      print('Collecting coverage data...');
      await coverage.collectCoverageIsolate(testIsolates.single.vmService,
          (String libraryName) => libraryName.contains(appName), packagesPath);
      try {
        await coverage.writeCoverageData(
          coverageOutputPath,
          packagesPath: packagesPath,
        );
      } catch (err) {
        print('Failed to collect coverage data: $err');
      }
    }
    for (var testIsolate in testIsolates) {
      testIsolate.dispose();
    }
    if (devtoolServer != null) {
      await devtoolServer.close();
    }
    exit(writer.exitCode);
  }

  var resident = Resident(
    config: config,
    compiler: compiler,
    testIsolate: testIsolates.single,
    writer: writer,
    testCompatMode: testCompatMode,
    packagesRootPath: packagesRootPath,
    tests: tests,
  );
  print('VM Service listening at ${testIsolates.single.vmServiceAddress}');
  await resident.start();
}
