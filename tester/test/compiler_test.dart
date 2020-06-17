// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:tester/src/compiler.dart';
import 'package:tester/src/config.dart';
import 'package:expect/expect.dart';

import 'fake_process_manager.dart';

Config createTestConfig(FileSystem fileSystem, TargetPlatform targetPlatform) {
  return Config(
    cacheName: 'linux-x64',
    flutterRoot: '/flutter',
    packageRootPath: '/project',
    targetPlatform: targetPlatform,
    tests: [Uri.file('/project/test/a_test.dart')],
    workspacePath: '/project',
    fileSystem: fileSystem,
  );
}

/// Validate that the compilation arguments are correct for the Dart VM.
Future<void> testDartVmCompile() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=vm',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.dart.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.dart.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.dart);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.dart,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: null,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri, Uri.parse('file:///project/main.TargetPlatform.dart.dart.dill'));
}

/// Validate that the compilation arguments are correct for the flutter_test.
Future<void> testFlutterCompile() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=flutter',
          '--sdk-root=/flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk',
          '-Ddart.vm.profile=false',
          '-Ddart.vm.product=false',
          '--track-widget-creation',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.flutter.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.flutter.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.flutter);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.flutter,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: null,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(
      uri, Uri.parse('file:///project/main.TargetPlatform.flutter.dart.dill'));
}

/// Validate that the compilation arguments are correct for Dart4Web
Future<void> testDartWebCompile() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=dartdevc',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/dart-sdk/lib/_internal/ddc_sdk.dill',
          '--debugger-module-names',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.web.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.web.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.web);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.web,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: null,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri, Uri.parse('file:///project/main.TargetPlatform.web.dart.dill'));
}

/// Validate that the compilation arguments are correct for Flutter Web
Future<void> testFlutterWebCompile() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=dartdevc',
          '-Ddart.vm.profile=false',
          '-Ddart.vm.product=false',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/flutter_web_sdk/kernel/flutter_ddc_sdk.dill',
          '--debugger-module-names',
          '--track-widget-creation',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.flutterWeb.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.flutterWeb.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.flutterWeb);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.flutterWeb,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: null,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri,
      Uri.parse('file:///project/main.TargetPlatform.flutterWeb.dart.dill'));
}

/// Validate that the compilation arguments are correct for the Dart VM
/// with experiments.
Future<void> testDartVmCompileWithExperiments() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=vm',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.dart.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
          '--enable-experiment=foo',
          '--enable-experiment=bar',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.dart.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.dart);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.dart,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: null,
    enabledExperiments: const <String>[
      'foo',
      'bar',
    ],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri, Uri.parse('file:///project/main.TargetPlatform.dart.dart.dill'));
}

/// Validate that the compilation arguments are correct for the Dart VM
/// with null safety.
Future<void> testDartVmCompileWithNullSafety() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=vm',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.dart.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
          '--null-safety',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.dart.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.dart);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.dart,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: true,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri, Uri.parse('file:///project/main.TargetPlatform.dart.dart.dill'));
}

/// Validate that the compilation arguments are correct for the Dart VM
/// with null safety disabled.
Future<void> testDartVmCompileWithDisableNullSafety() async {
  var controller = StreamController<List<int>>();
  var processManager = FakeProcessManager.list([
    FakeCommand(
        command: [
          '/flutter/bin/cache/dart-sdk/bin/dart',
          '--disable-dart-dev',
          '/flutter/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot',
          '--target=vm',
          '--sdk-root=/flutter/bin/cache/dart-sdk',
          '--platform=file:///flutter/bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
          '--enable-asserts',
          '--packages=file:///project/.packages',
          '--no-link-platform',
          '--output-dill=/project/main.TargetPlatform.dart.dart.dill',
          '--incremental',
          '--filesystem-root',
          '/',
          '--filesystem-root',
          '/project',
          '--filesystem-scheme',
          'org-dartlang-app',
          '--no-null-safety',
        ],
        stdin: IOSink(controller),
        stdout: '''result 97db4d90-861a-4b0d-951e-77319d74ce06
97db4d90-861a-4b0d-951e-77319d74ce06
+file:///a.dart
97db4d90-861a-4b0d-951e-77319d74ce06 /project/.dart_tool/tester/main.TargetPlatform.dart.dart.dill 0
''')
  ]);

  var fileSystem = MemoryFileSystem.test();
  var config = createTestConfig(fileSystem, TargetPlatform.dart);
  fileSystem.file('project/.packages')
    ..createSync(recursive: true)
    ..writeAsStringSync('project:project/');

  var compiler = Compiler(
    config: config,
    compilerMode: TargetPlatform.dart,
    fileSystem: fileSystem,
    processManager: processManager,
    timeout: -1,
    soundNullSafety: false,
    enabledExperiments: const <String>[],
  );

  var uri = await compiler.start({});

  expect(fileSystem.file('/project/main.dart').existsSync(), true);
  expect(uri, Uri.parse('file:///project/main.TargetPlatform.dart.dart.dill'));
}
