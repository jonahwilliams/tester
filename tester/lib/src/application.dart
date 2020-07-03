// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Platform;
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';

import 'coverage.dart';
import 'logging.dart';
import 'platform.dart';
import 'test_info.dart';
import 'compiler.dart';
import 'config.dart';
import 'isolate.dart';
import 'resident.dart';
import 'runner.dart';
import 'web_runner.dart';
import 'writer.dart';

/// Select a reasonable number of shards to run tests on if it was not specified.
///
/// Assume that one test file represents a minimum amount of work to make another
/// runner worth spinning up.
int selectCores(Platform platform, List<Uri> tests) {
  return math.max(math.min(tests.length, platform.numberOfProcessors - 1), 1);
}

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
  @required int times,
  @required int randomSeed,
  @required bool headless,
  @required bool compileOnly,
  @required bool runOnly,
}) async {
  var logger = Logger('tool');
  if (verbose) {
    logger.onRecord.listen((record) {
      print(record.message);
    });
  }
  if (!batchMode || debugger) {
    concurrency = 1;
  }
  if (concurrency == null) {
    concurrency = selectCores(const LocalPlatform(), tests);
    logger.log(Level.INFO, 'Selected $concurrency concurrency level');
  }
  var fileSystem = const LocalFileSystem();
  var packagesUri = fileSystem
      .file(fileSystem.path.join(packagesRootPath, '.packages'))
      .absolute
      .uri;
  var packageConfig = await measureCommand(
    () => loadPackageConfigUri(packagesUri),
    'package_config',
    logger,
  );
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
  measureCommand(infoProvider.loadTestInfos, 'cached_test_info', logger);
  var testInfos = await measureCommand(
      () => infoProvider.collectTestInfos(tests), 'parse_tests', logger);
  Uri result;
  if (!runOnly) {
    result = await measureCommand(
        () => compiler.start(testInfos), 'compile', logger);
    if (result == null) {
      exit(1);
    }
  } else {
    result = fileSystem
        .file(fileSystem.path
            .join(workspacePath, 'main.${targetPlatform}.dart.dill'))
        .absolute
        .uri;
  }
  if (compileOnly) {
    exit(0);
  }

  var testIsolates = <TestIsolate>[];
  var loadingIsolates = <Future<void>>[];
  for (var i = 0; i < concurrency; i++) {
    TestIsolate testIsolate;
    switch (targetPlatform) {
      case TargetPlatform.dart:
        var testRunner = VmTestRunner(
          dartExecutable: config.dartPath,
        );
        testIsolate = VmTestIsolate(
          testRunner: testRunner,
          compileExpression: compiler.compileExpression,
          logger: logger,
        );
        break;
      case TargetPlatform.flutter:
        var testRunner = FlutterTestRunner(
          flutterTesterPath: config.flutterTesterPath,
        );
        testIsolate = VmTestIsolate(
          testRunner: testRunner,
          compileExpression: compiler.compileExpression,
          logger: logger,
        );
        break;
      case TargetPlatform.web:
        var testRunner = ChromeTestRunner(
          dartSdkFile: File(config.webDartSdk),
          dartSdkSourcemap: File(config.webDartSdkSourcemaps),
          stackTraceMapper: File(config.stackTraceMapper),
          requireJS: File(config.requireJS),
          config: config,
          packagesRootPath: packagesRootPath,
          headless: headless,
          packageConfig: packageConfig,
          expressionCompiler: compiler,
          logger: logger,
        );
        testIsolate = WebTestIsolate(
          testRunner: testRunner,
          logger: logger,
        );
        break;
      case TargetPlatform.flutterWeb:
        var testRunner = ChromeTestRunner(
          dartSdkFile: File(config.flutterWebDartSdk),
          dartSdkSourcemap: File(config.flutterWebDartSdkSourcemaps),
          stackTraceMapper: File(config.stackTraceMapper),
          requireJS: File(config.requireJS),
          packagesRootPath: packagesRootPath,
          config: config,
          headless: headless,
          packageConfig: packageConfig,
          expressionCompiler: compiler,
          logger: logger,
        );
        testIsolate = WebTestIsolate(
          testRunner: testRunner,
          logger: logger,
        );
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
  await measureCommand(
      () => Future.wait(loadingIsolates), 'bootstrap_test_runners', logger);

  var writer = TestWriter(
    projectRoot: packagesRootPath,
    verbose: verbose,
    ci: ci,
    testCount: testInfos.testCount * times,
  );

  var random = math.Random(randomSeed);
  if (batchMode) {
    writer.writeHeader();
    var testOrder = <TestInfo>[
      for (var testFileUri in testInfos.testInformation.keys)
        for (var testInfo in testInfos.testInformation[testFileUri])
          for (var i = 0; i < times; i++) testInfo
    ]..shuffle(random);

    if (debugger) {
      print('VM Service listening at: ${testIsolates.single.vmServiceAddress} .'
          'Press enter to begin test execution.');
      await stdin.firstWhere((element) => true);
      print('Starting...');
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < concurrency; i++)
        (() async {
          while (testOrder.isNotEmpty) {
            var nextTest = testOrder.removeLast();
            var testResult = await testIsolates[i].runTest(nextTest);
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
      await testIsolate.dispose();
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
  print('VM Service listening at ${testIsolates.single.vmServiceAddress}.'
      ' Press q/Q to quit.');
  await resident.start();
  stdin.echoMode = false;
  stdin.lineMode = false;
  stdin.transform(utf8.decoder).listen((String char) async {
    if (char == 'q' || char == 'Q') {
      await resident.dispose();
      exit(0);
    }
  });
}
