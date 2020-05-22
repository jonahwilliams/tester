// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

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
  ..addOption(
    'platform',
    help: 'The platform to run tests on.',
    allowed: _allowedPlatforms,
    defaultsTo: 'dart',
  )
  ..addMultiOption('test');

Future<void> main(List<String> args) async {
  var fileSystem = const LocalFileSystem();
  var platform = const LocalPlatform();

  var argResults = argParser.parse(args);
  var flutterRoot = fileSystem.file(platform.resolvedExecutable)
    .parent
    .parent
    .parent
    .parent
    .parent.path;
  String cacheName;
  if (platform.isMacOS) {
    cacheName = 'darwin-x64';
  } else if (platform.isLinux) {
    cacheName = 'linux-x64';
  } else if (platform.isWindows) {
    cacheName = 'windows-x64';
  } else {
    print('Unsupported platform $platform');
    return;
  }

  List<Uri> tests;
  if (argResults.wasParsed('test')) {
    tests = (argResults['test'] as List<String>)
        .map((path) => fileSystem.file(path).uri)
        .toList();
  } else {
    tests = fileSystem
        .directory(argResults['project-root'] ?? '.')
        .childDirectory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'))
        .map((file) => file.absolute.uri)
        .toList();
  }

  var projectDirectory =
      argResults['project-root'] as String ?? fileSystem.currentDirectory.path;

  runApplication(
    batchMode: argResults['batch'] as bool,
    fileSystem: fileSystem,
    processManager: const LocalProcessManager(),
    config: Config(
      targetPlatform: TargetPlatform
          .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
      workspacePath: projectDirectory,
      packageRootPath: projectDirectory,
      tests: tests,
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
      platformDillUri: fileSystem
          .file(fileSystem.path.join(
            flutterRoot,
            'bin',
            'cache',
            'dart-sdk',
            'lib',
            '_internal',
            'vm_platform_strong.dill',
          ))
          .uri,
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
