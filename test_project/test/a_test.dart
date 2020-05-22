// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

void testThatOneIsOne() {
  if (1 == 2) {
    throw Exception('bad222');
  }
}

Future<void> testFoo() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
  if ('asdsaad'.isEmpty) {
    throw Exception('');
  }
}

void testSomethingElse() {
  if ('aasdasd' == 'adad') {
    throw Exception();
  }
}