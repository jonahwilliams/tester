// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'package:expect/expect.dart';
import 'package:tester/src/coverage.dart';

/// When coverage is writen with no measurements, returns false and no-ops.
void testNoCoverageReturns() async {
  var service = CoverageService();

  expect(
    await service.writeCoverageData('lcov.info', packagesPath: '.packages'),
    false,
  );
}
