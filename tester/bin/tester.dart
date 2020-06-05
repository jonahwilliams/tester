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
  ..addFlag('watch', abbr: 'b', help: 'Watch file changes and re-run tests.')
  ..addFlag('verbose', abbr: 'v')
  ..addOption('flutter-root',
      help:
          'the path to the root of a flutter checkout, if it is not available on the PATH')
  ..addFlag('ci')
  ..addOption(
    'platform',
    help: 'The platform to run tests on.',
    allowed: _allowedPlatforms,
    defaultsTo: 'dart',
  );

Future<void> main(List<String> args) async {
  if (!File(path.join(Directory.current.path, 'pubspec.yaml')).existsSync()) {
    print('tester must be run in a directory with a pubspec.yaml.');
    exit(1);
  }

  var argResults = argParser.parse(args);

  String flutterRoot;
  if (argResults['flutter-root'] != null) {
    flutterRoot = argResults['flutter-root'] as String;
  } else if (Platform.isWindows) {
    flutterRoot = File((await Process.run('where', <String>['flutter']))
            .stdout
            .split('\n')
            .first as String)
        .parent
        .parent
        .path;
  } else {
    flutterRoot = File((await Process.run('which', <String>['flutter']))
            .stdout
            .split('\n')
            .first as String)
        .parent
        .parent
        .path;
  }

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

  var projectDirectory = Directory.current.path;

  List<Uri> tests;
  if (argResults.rest.isEmpty) {
    tests = Directory(path.join(projectDirectory, 'test'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'))
        .map((file) => file.absolute.uri)
        .toList();
  } else {
    tests =
        argResults.rest.map((String path) => File(path).absolute.uri).toList();
  }

  var workspace =
      Directory(path.join(projectDirectory, '.dart_tool', 'tester'));
  if (!workspace.existsSync()) {
    workspace.createSync(recursive: true);
  }

  var config = Config(
    targetPlatform: TargetPlatform
        .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
    workspacePath: workspace.path,
    packageRootPath: Directory(projectDirectory).absolute.path,
    tests: tests,
    cacheName: cacheName,
    flutterRoot: flutterRoot,
  );
  runApplication(
    verbose: argResults['verbose'] as bool,
    batchMode: !(argResults['watch'] as bool),
    config: config,
    ci: argResults['ci'] as bool,
  );
}
