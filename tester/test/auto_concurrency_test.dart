// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8

import 'package:expect/expect.dart';
import 'package:tester/src/platform.dart';
import 'package:tester/src/application.dart';

/// Ensure core selection works reasonably well for certain configurations.
void testCoreSelection() {
  expect(selectCores(FakePlatform(numberOfProcessors: 0), <Uri>[]), 1);
  expect(selectCores(FakePlatform(numberOfProcessors: 8), <Uri>[]), 1);
  expect(
      selectCores(FakePlatform(numberOfProcessors: 0), <Uri>[
        Uri.file('foo'),
        Uri.file('bar'),
      ]),
      1);
  expect(
      selectCores(FakePlatform(numberOfProcessors: 8), <Uri>[
        Uri.file('foo'),
        Uri.file('bar'),
      ]),
      2);
  expect(
      selectCores(FakePlatform(numberOfProcessors: 8), <Uri>[
        Uri.file('foo'),
        Uri.file('bar'),
        Uri.file('foo'),
        Uri.file('bar'),
        Uri.file('foo'),
        Uri.file('bar'),
        Uri.file('foo'),
        Uri.file('bar'),
        Uri.file('foo'),
        Uri.file('bar'),
      ]),
      7);
}
