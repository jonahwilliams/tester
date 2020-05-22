// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// Configuration necessary to bootstrap the test runner.
class Config {
  const Config({
    @required this.dartPath,
    @required this.frontendServerPath,
    @required this.workspacePath,
    @required this.packageRootPath,
    @required this.tests,
    @required this.dartSdkRoot,
    @required this.platformDillUri,
    @required this.flutterPatchedSdkRoot,
    @required this.targetPlatform,
    @required this.flutterTesterPath,
  });

  /// The file path to the dart executable.
  final String dartPath;

  /// The file path to the frontend_server executable.
  final String frontendServerPath;

  /// The file path to a workspace directory.
  ///
  /// This is used to generated temporary files or other intermediate
  /// artifacts.
  final String workspacePath;

  /// The file path to the directory which contains `lib`, `test`, and
  /// `pubspec.yaml`.
  final String packageRootPath;

  /// The file path to the root of the current Dart SDK.
  final String dartSdkRoot;

  /// The file path to the root of the current Flutter patched SDK.
  final String flutterPatchedSdkRoot;

  /// The file URI to the platform dill for the current SDK.
  final Uri platformDillUri;

  /// The file paths to the tests that should be executed.
  final List<Uri> tests;

  /// The currently targeted platform.
  final TargetPlatform targetPlatform;

  /// The path to the flutter test device.
  final String flutterTesterPath;
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
