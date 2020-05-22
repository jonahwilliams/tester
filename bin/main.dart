// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tester/src/config.dart';
import 'package:tester/tester.dart';
import 'package:path/path.dart' as path;

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
  var argResults = argParser.parse(args);
  var flutterRoot = File(Platform.resolvedExecutable)
    .parent
    .parent
    .parent
    .parent
    .parent.path;
  String cacheName;
  if (Platform.isMacOS) {
    cacheName = 'darwin-x64';
  } else if (Platform.isLinux) {
    cacheName = 'linux-x64';
  } else if (Platform.isWindows) {
    cacheName = 'windows-x64';
  } else {
    print('Unsupported platform ${Platform.localeName}');
    return;
  }

  List<Uri> tests;
  if (argResults.wasParsed('test')) {
    tests = (argResults['test'] as List<String>)
        .map((path) => File(path).uri)
        .toList();
  } else {
    tests = Directory(path.join(argResults['project-root'] as String ?? '.', 'test'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'))
        .map((file) => file.absolute.uri)
        .toList();
  }

  var projectDirectory =
      argResults['project-root'] as String ?? Directory.current.path;

  runApplication(
    batchMode: argResults['batch'] as bool,
    config: Config(
      targetPlatform: TargetPlatform
          .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
      workspacePath: projectDirectory,
      packageRootPath: projectDirectory,
      tests: tests,
      frontendServerPath: path.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'engine',
        cacheName,
        'frontend_server.dart.snapshot',
      ),
      dartPath: path.join(
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
        'bin',
        'dart',
      ),
      dartSdkRoot: path.join(
        flutterRoot,
        'bin',
        'cache',
        'dart-sdk',
      ),
      platformDillUri: File(path.join(
            flutterRoot,
            'bin',
            'cache',
            'dart-sdk',
            'lib',
            '_internal',
            'vm_platform_strong.dill',
          ))
          .uri,
      flutterPatchedSdkRoot: path.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'common',
        'flutter_patched_sdk',
      ),
      flutterTesterPath: path.join(
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
