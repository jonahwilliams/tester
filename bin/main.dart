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
  ..addOption(
    'platform',
    help: 'The platform to run tests on.',
    allowed: _allowedPlatforms,
    defaultsTo: 'dart',
  );

Future<void> main(List<String> args) async {
  var argResults = argParser.parse(args);
  String flutterRoot;
  if (Platform.isWindows) {
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

  var projectDirectory = argResults.rest.first ?? Directory.current.path;

  final tests = Directory(path.join(projectDirectory, 'test'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('_test.dart'))
      .map((file) => file.absolute.uri)
      .toList();

  var workspace =
      Directory(path.join(projectDirectory, '.dart_tool', 'tester'));
  if (!workspace.existsSync()) {
    workspace.createSync(recursive: true);
  }

  runApplication(
    verbose: argResults['verbose'] as bool,
    batchMode: !(argResults['watch'] as bool),
    config: Config(
      targetPlatform: TargetPlatform
          .values[_allowedPlatforms.indexOf(argResults['platform'] as String)],
      workspacePath: workspace.path,
      packageRootPath: Directory(projectDirectory).absolute.path,
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
      )).uri,
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
        'bin/cache/artifacts/engine',
        cacheName,
        'flutter_tester',
      ),
      flutterWebPlatformDillUri: File(path.join(
        flutterRoot,
        'bin/cache/flutter_web_sdk/kernel/flutter_ddc_sdk.dill',
      )).uri,
      flutterWebDartSdk: path.join(
        flutterRoot,
        'bin/cache/flutter_web_sdk/kernel/amd/dart_sdk.js',
      ),
      flutterWebDartSdkSourcemaps: path.join(
        flutterRoot,
        'bin/cache/flutter_web_sdk/kernel/amd/dart_sdk.js.map',
      ),
      webDartSdk: path.join(
        flutterRoot,
        'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/dart_sdk.js',
      ),
      webDartSdkSourcemaps: path.join(
        flutterRoot,
        'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/dart_sdk.js.map',
      ),
      requireJS: path.join(
        flutterRoot,
        'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/require.js',
      ),
      stackTraceMapper: path.join(
        flutterRoot,
        'bin/cache/dart-sdk/lib/dev_compiler/web/dart_stack_trace_mapper.js',
      )
    ),
  );
}
