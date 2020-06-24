// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:devtools_server/devtools_server.dart' as devtools_server;
import 'package:package_config/package_config.dart';

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
  @required TargetPlatform targetPlatform,
  @required List<Uri> tests,
  @required String packagesRootPath,
  @required String workspacePath,
}) async {
  if (!batchMode || debugger) {
    concurrency = 1;
  }
  var fileSystem = const LocalFileSystem();
  var packagesUri = fileSystem
      .file(fileSystem.path.join(packagesRootPath, '.packages'))
      .absolute
      .uri;
  var packageConfig = await loadPackageConfigUri(packagesUri);
  var testCompatMode = packageConfig['test_api'] != null;
  var coverage = CoverageService();
  var compiler = Compiler(
    config: config,
    compilerMode: targetPlatform,
    timeout: debugger ? -1 : timeout,
    soundNullSafety: soundNullSafety,
    enabledExperiments: enabledExperiments,
    packageConfig: packageConfig,
    workspacePath: workspacePath,
    packagesRootPath: packagesRootPath,
    testCompatMode: testCompatMode,
    packagesUri: packagesUri,
  );
  var infoProvider = TestInformationProvider(
    testCompatMode: testCompatMode,
    packagesRootPath: packagesRootPath,
    testManifestPath: fileSystem.path.join(
      workspacePath,
      'info_cache.json',
    ),
  );
  infoProvider.loadTestInfos();
  var testInfos = infoProvider.collectTestInfos(tests);
  var result = await compiler.start(testInfos);
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
    testCount: testInfos.testCount,
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
    var testOrder = <TestInfo>[
      for (var testFileUri in testInfos.testInformation.keys)
        for (var testInfo in testInfos.testInformation[testFileUri]) testInfo
    ]..shuffle();

    await Future.wait(<Future<void>>[
      for (var i = 0; i < concurrency; i++)
        (() async {
          while (testOrder.isNotEmpty) {
            var nextTest = testOrder.removeLast();
            var testResult = await testIsolates[i].runTest(nextTest, debugger);
            writer.writeTest(testResult, nextTest);
          }
        })()
    ]);

    writer.writeSummary();
    if (coverageOutputPath != null) {
      var packagesPath = fileSystem.path.join(packagesRootPath, '.packages');
      print('Collecting coverage data...');
      await Future.wait(<Future<void>>[
        for (var i = 0; i < concurrency; i++)
          coverage.collectCoverageIsolate(
              testIsolates[i].vmService,
              (String libraryName) => libraryName.contains(appName),
              packagesPath)
      ]);
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
    infoProvider.storeTestInfos();
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
