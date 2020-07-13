// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';

/// Configuration necessary to bootstrap the test runner.
class Config {
  factory Config({
    @required String flutterRoot,
    @required List<Uri> tests,
    @required String cacheName,
    FileSystem fileSystem = const LocalFileSystem(),
  }) {
    if (flutterRoot != null) {
      return Config._(
        frontendServerPath: fileSystem.path.join(
          flutterRoot,
          'bin/cache/artifacts/engine',
          cacheName,
          'frontend_server.dart.snapshot',
        ),
        dartPath: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk/bin/dart',
        ),
        dartSdkRoot: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk',
        ),
        platformDillUri: fileSystem
            .file(fileSystem.path.join(
              flutterRoot,
              'bin/cache/dart-sdk/lib/_internal/vm_platform_strong.dill',
            ))
            .absolute
            .uri,
        flutterPatchedSdkRoot: fileSystem.path.join(
          flutterRoot,
          'bin/cache/artifacts/engine/common/flutter_patched_sdk',
        ),
        flutterTesterPath: fileSystem.path.join(
          flutterRoot,
          'bin/cache/artifacts/engine',
          cacheName,
          'flutter_tester',
        ),
        flutterWebPlatformDillUri: fileSystem
            .file(
              fileSystem.path.join(
                flutterRoot,
                'bin/cache/flutter_web_sdk/kernel/flutter_ddc_sdk.dill',
              ),
            )
            .uri,
        flutterWebSdkSources: fileSystem.path.join(
          flutterRoot,
          'bin/cache/flutter_web_sdk/',
        ),
        flutterWebDartSdk: fileSystem.path.join(
          flutterRoot,
          'bin/cache/flutter_web_sdk/kernel/amd/dart_sdk.js',
        ),
        flutterWebDartSdkSourcemaps: fileSystem.path.join(
          flutterRoot,
          'bin/cache/flutter_web_sdk/kernel/amd/dart_sdk.js.map',
        ),
        dartWebPlatformDillUri: fileSystem
            .file(fileSystem.path.join(
              flutterRoot,
              'bin/cache/dart-sdk/lib/_internal/ddc_sdk.dill',
            ))
            .uri,
        webDartSdk: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/dart_sdk.js',
        ),
        webDartSdkSourcemaps: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/dart_sdk.js.map',
        ),
        requireJS: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/require.js',
        ),
        stackTraceMapper: fileSystem.path.join(
          flutterRoot,
          'bin/cache/dart-sdk/lib/dev_compiler/web/dart_stack_trace_mapper.js',
        ),
      );
    }
    // Running with Dart SDK.
    var dartPath = Platform.resolvedExecutable;
    var dartSdkPath = fileSystem.file(dartPath).parent.parent.path;
    return Config._(
      frontendServerPath: fileSystem.path.join(
        dartSdkPath,
        'bin/snapshots/frontend_server.dart.snapshot',
      ),
      dartPath: dartPath,
      dartSdkRoot: dartSdkPath,
      platformDillUri: fileSystem
          .file(fileSystem.path.join(
            dartSdkPath,
            'lib/_internal/vm_platform_strong.dill',
          ))
          .absolute
          .uri,
      flutterPatchedSdkRoot: null,
      flutterTesterPath: null,
      flutterWebPlatformDillUri: null,
      flutterWebDartSdk: null,
      flutterWebDartSdkSourcemaps: null,
      flutterWebSdkSources: null,
      dartWebPlatformDillUri: fileSystem
          .file(fileSystem.path.join(
            dartSdkPath,
            'lib/_internal/ddc_sdk.dill',
          ))
          .uri,
      webDartSdk: fileSystem.path.join(
        dartSdkPath,
        'lib/dev_compiler/kernel/amd/dart_sdk.js',
      ),
      webDartSdkSourcemaps: fileSystem.path.join(
        dartSdkPath,
        'lib/dev_compiler/kernel/amd/dart_sdk.js.map',
      ),
      requireJS: fileSystem.path.join(
        flutterRoot,
        'bin/cache/dart-sdk/lib/dev_compiler/kernel/amd/require.js',
      ),
      stackTraceMapper: fileSystem.path.join(
        dartSdkPath,
        'lib/dev_compiler/web/dart_stack_trace_mapper.js',
      ),
    );
  }

  const Config._({
    @required this.dartPath,
    @required this.frontendServerPath,
    @required this.dartSdkRoot,
    @required this.platformDillUri,
    @required this.flutterPatchedSdkRoot,
    @required this.flutterTesterPath,
    @required this.flutterWebPlatformDillUri,
    @required this.flutterWebDartSdk,
    @required this.flutterWebDartSdkSourcemaps,
    @required this.webDartSdk,
    @required this.webDartSdkSourcemaps,
    @required this.stackTraceMapper,
    @required this.requireJS,
    @required this.dartWebPlatformDillUri,
    @required this.flutterWebSdkSources,
  });

  /// The root of the flutter web sdk source code.
  final String flutterWebSdkSources;

  /// The file path to the dart executable.
  final String dartPath;

  /// The file path to the frontend_server executable.
  final String frontendServerPath;

  /// The file path to the root of the current Dart SDK.
  final String dartSdkRoot;

  /// The file path to the root of the current Flutter patched SDK.
  final String flutterPatchedSdkRoot;

  /// The file URI to the platform dill for the current SDK.
  final Uri platformDillUri;

  /// The file URI to the platform dill for flutter web applications.
  final Uri flutterWebPlatformDillUri;

  /// The path to the flutter test device.
  final String flutterTesterPath;

  final String flutterWebDartSdk;
  final String flutterWebDartSdkSourcemaps;

  final String webDartSdk;
  final String webDartSdkSourcemaps;

  final String stackTraceMapper;
  final String requireJS;

  final Uri dartWebPlatformDillUri;
}

/// The compiler configuration for the targeted platform.
enum TargetPlatform {
  /// The Dart VM.
  dart,

  /// Dart in web browsers.
  web,

  /// The Flutter engine,
  flutter,

  /// The Flutter web engine,
  flutterWeb,
}
