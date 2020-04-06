// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:platform/platform.dart';
import 'package:process/process.dart';
import 'package:tester/src/config.dart';
import 'package:tester/tester.dart';

const _allowedPlatforms = ['dart', 'web', 'flutter', 'flutter_web'];

final argParser = ArgParser()
  ..addFlag('batch', abbr: 'b', help: 'Whether to run tests in batch mode.')
  ..addOption('project-root', help: 'The path to the project under test')
  ..addOption('flutter-root', help: 'The file path to the Flutter SDK.')
  ..addOption(
    'platform',
    help: 'The platform to run tests on.',
    allowed: _allowedPlatforms,
  )
  ..addMultiOption('test');

Future<void> main(List<String> args) async {
  var argResults = argParser.parse(args);
  var flutterRoot = argResults['flutter-root'] as String;
  var fileSystem = const LocalFileSystem();
  var platform = const LocalPlatform();
  String cacheName;
  if (platform.isMacOS) {
    cacheName = 'darwin-x64';
  } else if (platform.isLinux) {
    cacheName = 'linux-x64';
  } else if (platform.isWindows) {
    cacheName = 'window-x64';
  } else {
    print('Unsupported platform $platform');
    return;
  }

  List<String> testFiles;
  if (argResults.wasParsed('test')) {
    testFiles = argResults['test'] as List<String>;
  } else {
    testFiles = fileSystem
        .directory(argResults['project-root'])
        .childDirectory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'))
        .map((file) => fileSystem.path
            .relative(file.path, from: argResults['project-root'] as String))
        .toList();
  }
  runApplication(
    batchMode: argResults['batch'] as bool,
    fileSystem: const LocalFileSystem(),
    processManager: const LocalProcessManager(),
    config: Config(
      targetPlatform: TargetPlatform
          .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
      workspacePath: argResults['project-root'] as String,
      packageRootPath: argResults['project-root'] as String,
      testPaths: testFiles,
      frontendServerPath: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'engine',
        cacheName,
        'frontend_server.dart.snapshot',
      ),
      dartPath: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
        'bin',
        'dart',
      ),
      dartSdkRoot: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
      ),
      platformDillPath: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
        'lib',
        '_internal',
        'vm_platform_strong.dill',
      ),
      flutterPatchedSdkRoot: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'common',
        'flutter_patched_sdk',
      ),
      flutterTesterPath: fileSystem.path.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'engine',
        cacheName,
        'flutter_tester',
      ),
    ),
  );
}
