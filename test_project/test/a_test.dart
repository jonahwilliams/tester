// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// [test] This is a test. it will pass since there is never a thrown
/// condition, even though it isn't really "testing" anything at all.
void testThatOneIsOne() {
  if (1 == 1) {
    throw Exception('bad222');
  }
}

/// [test] This is a test.
Future<void> testFoo() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
  if ('asdsaad'.isNotEmpty) {
    throw Exception('');
  }
}

/// [test] This is a test.
void testSomethingElse() {
  if ('aasdasd' == 'adad') {
    throw Exception();
  }
}