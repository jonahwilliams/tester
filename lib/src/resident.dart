// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dart_console/dart_console.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

import 'compiler.dart';
import 'config.dart';
import 'isolate.dart';
import 'test_info.dart';
import 'writer.dart';

/// A resident process which routes commands to the appropriate action.
///
/// This only supports a simple workflow of recompiling, reloading, and
/// rerunning.
class Resident {
  Resident({
    @required this.compiler,
    @required this.config,
    @required this.testIsolate,
    @required this.writer,
  });

  final ProjectFileInvalidator projectFileInvalidator =
      ProjectFileInvalidator();
  final Console console = Console();
  final Compiler compiler;
  final Config config;
  final TestIsolate testIsolate;
  final TestWriter writer;
  final infoProvider = TestInformationProvider();
  Map<Uri, List<TestInfo>> testInformation;

  Future<void> start() async {
    testInformation = <Uri, List<TestInfo>>{};
    for (var testFileUri in config.tests) {
      testInformation[testFileUri] = infoProvider.collectTestInfo(testFileUri);
    }

    var pendingTest = false;
    var controller = StreamController<WatchEvent>();
    Watcher(path.join(config.packageRootPath, 'lib'))
        .events
        .listen(controller.add);
    Watcher(path.join(config.packageRootPath, 'test'))
        .events
        .listen(controller.add);
    controller.stream
        .debounce(const Duration(milliseconds: 100))
        .listen((WatchEvent event) async {
      if (path.extension(event.path) != '.dart') {
        return;
      }
      if (pendingTest) {
        return;
      }
      if (path.isWithin(path.join(config.packageRootPath, 'lib'), event.path)) {
        var invalidated = await projectFileInvalidator.findInvalidated(
          lastCompiled: compiler.lastCompiled,
          urisToMonitor: compiler.dependencies,
          packagesUri:
              Directory(path.join(config.packageRootPath, '.packages')).uri,
        );
        if (invalidated.isEmpty) {
          return;
        }
        var result = await compiler.recompile(invalidated, testInformation);
        if (result == null) {
          return;
        }
        pendingTest = true;
        console.clearScreen();
        writer.writeHeader();
        for (var testFileUri in testInformation.keys) {
          for (var testInfo in testInformation[testFileUri]) {
            var testResult = await testIsolate.runTest(testInfo);
            writer.writeTest(testResult, testInfo);
          }
        }
        writer.writeSummary();
        pendingTest = false;
        return;
      }

      if (event.type != ChangeType.MODIFY) {
        return;
      }
      var testUri = File(event.path).absolute.uri;
      if (testInformation[testUri] == null) {
        return;
      }
      var invalidated = await projectFileInvalidator.findInvalidated(
        lastCompiled: compiler.lastCompiled,
        urisToMonitor: compiler.dependencies,
        packagesUri:
            Directory(path.join(config.packageRootPath, '.packages')).uri,
      );
      if (invalidated.isEmpty) {
        return;
      }
      pendingTest = true;
      console.clearScreen();
      for (var testFileUri in invalidated) {
        if (testInformation.containsKey(testFileUri)) {
          testInformation[testFileUri] =
              infoProvider.collectTestInfo(testFileUri);
        }
      }
      var result = await compiler.recompile(invalidated, testInformation);
      if (result != null) {
        testInformation[testUri] = infoProvider.collectTestInfo(testUri);
        await testIsolate.reload(result);
      }
      var testInfos = testInformation[testUri];
      writer.writeHeader();
      for (var testInfo in testInfos) {
        var testResult = await testIsolate.runTest(testInfo);
        writer.writeTest(testResult, testInfo);
      }
      writer.writeSummary();
      pendingTest = false;
    });
  }

  Future<void> dispose() async {
    await testIsolate.dispose();
    compiler.dispose();
  }
}
