// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

void main() async {
  expect(2, greaterThan(1));
  throws(() => Exception(), isA<Exception>());
  await throwsAsync(() async {
    await null;
    throw Exception();
  }, isA<Exception>());
}
