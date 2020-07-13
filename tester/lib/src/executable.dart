// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:tester/src/config.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'application.dart';

const _allowedPlatforms = ['dart', 'web', 'flutter', 'flutter_web'];

final argParser = ArgParser()
  ..addFlag('watch', abbr: 'b', help: 'Watch file changes and re-run tests.')
  ..addFlag(
    'coverage',
    help: 'Measure code coverage during test execution. By default this is '
        'output to coverage/lcof.info. Use the option --coverage-output to '
        'configure a different file.',
  )
  ..addOption(
    'coverage-output',
    help: 'The output file for code coverage measurements.',
    defaultsTo: 'coverage/lcov.info',
  )
  ..addFlag('verbose', abbr: 'v')
  ..addFlag('ci', help: 'Run with simpler output optimized for running on CI.')
  ..addOption(
    'platform',
    help:
        'The Dart platform where tests will be run. This affects the available '
        'dart libraries as well as the compilation strategy.',
    allowed: _allowedPlatforms,
    defaultsTo: 'dart',
  )
  ..addOption(
    'concurrency',
    abbr: 'j',
    help: 'The number of test isolates to run concurrently in batch mode. '
        'This option only takes effect in batch mode without --coverage or '
        '--debugger. If not provided, tester will attempt to select a reasonable '
        'default based on the number of available cores and size of the provided '
        'test suite.',
  )
  ..addOption(
    'timeout',
    help: 'The maximum number of seconds a single test can elapse before it is '
        'consider a failure. To disable timeouts, pass -1 as a value.',
    defaultsTo: '15',
  )
  ..addMultiOption(
    'enable-experiment',
    help: 'The name of an experimental Dart feature to enable. For more info '
        'see: https://github.com/dart-lang/sdk/blob/master/docs/process/'
        'experimental-flags.md',
  )
  ..addFlag(
    'sound-null-safety',
    help: 'Whether to override the default null safety setting.',
    defaultsTo: null,
  )
  ..addFlag(
    'debugger',
    help:
        'launch the devtools debugger and pause each test to allow stepping. ',
    defaultsTo: false,
  )
  ..addOption('flutter-root',
      help: 'The path to the root of a flutter checkout.')
  ..addOption(
    'times',
    help: 'The number of times to run each test.',
    defaultsTo: '1',
  )
  ..addOption(
    'random-seed',
    help: 'Provide a number to configure the random seed used to shuffle test '
        'orderin. If not provided, tests will be shuffled in a different order '
        'on each run.',
  )
  ..addFlag('headless',
      defaultsTo: false,
      help: 'Whether to run the tester/browser in headless mode.')
  ..addFlag('run-only', hide: true)
  ..addFlag('compile-only', hide: true)
  ..addFlag('no-debug', hide: true);

Future<void> main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    print(argParser.usage);
    return;
  }

  var pubspecFile = File(path.join(Directory.current.path, 'pubspec.yaml'));
  if (!pubspecFile.existsSync()) {
    print('tester must be run in a directory with a pubspec.yaml.');
    exit(1);
  }
  var appName = (loadYamlNode(pubspecFile.readAsStringSync())
      as YamlMap)['name'] as String;

  var argResults = argParser.parse(args);

  String flutterRoot;
  if (argResults['flutter-root'] != null) {
    flutterRoot = path.normalize(argResults['flutter-root'] as String);
  } else if (Platform.environment['FLUTTER_ROOT'] != null) {
    flutterRoot = path.normalize(Platform.environment['FLUTTER_ROOT']);
  } else if (Platform.isWindows) {
    try {
      var dartExecutable = File(Platform.resolvedExecutable);
      var candidateFlutterRoot =
          dartExecutable.parent.parent.parent.parent.parent;
      if (candidateFlutterRoot.existsSync()) {
        flutterRoot = candidateFlutterRoot.path;
      }
    } on FileSystemException {
      // Do nothing, flutter was not located.
    }
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
    var testDirectory = Directory(path.join(projectDirectory, 'test'));
    if (!testDirectory.existsSync()) {
      tests = <Uri>[];
    } else {
      tests = Directory(path.join(projectDirectory, 'test'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('_test.dart'))
          .map((file) => file.absolute.uri)
          .toList();
    }
  } else {
    tests = globTests(argResults.rest);
  }

  var workspace =
      Directory(path.join(projectDirectory, '.dart_tool', 'tester'));
  if (!workspace.existsSync()) {
    workspace.createSync(recursive: true);
  }

  var config = Config(
    tests: tests,
    cacheName: cacheName,
    flutterRoot: flutterRoot,
  );
  runApplication(
    verbose: argResults['verbose'] as bool,
    batchMode: !(argResults['watch'] as bool),
    config: config,
    ci: argResults['ci'] as bool,
    appName: appName,
    coverageOutputPath: (argResults['coverage'] as bool)
        ? argResults['coverage-output'] as String
        : null,
    timeout: int.tryParse(argResults['timeout'] as String) ?? 15,
    concurrency: argResults.wasParsed('concurrency')
        ? int.tryParse(argResults['concurrency'] as String)
        : null,
    enabledExperiments: argResults['enable-experiment'] as List<String>,
    soundNullSafety: argResults['sound-null-safety'] as bool,
    debugger: argResults['debugger'] as bool,
    targetPlatform: TargetPlatform
        .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
    workspacePath: workspace.path,
    packagesRootPath: Directory(projectDirectory).absolute.path,
    tests: tests,
    times: int.tryParse(argResults['times'] as String),
    randomSeed: argResults.wasParsed('random-seed')
        ? int.tryParse(argResults['random-seed'] as String)
        : null,
    headless: argResults['headless'] as bool,
    compileOnly: argResults['compile-only'] as bool,
    runOnly: argResults['run-only'] as bool,
    noDebug: argResults['no-debug'] as bool,
  );
}

List<Uri> globTests(List<String> inputs) {
  List<Uri> recurse(String path) {
    if (FileSystemEntity.isDirectorySync(path)) {
      return Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('_test.dart'))
          .map((file) => file.uri)
          .toList();
    }
    return <Uri>[File(path).uri];
  }

  return inputs.map(recurse).expand((element) => element).toList();
}
