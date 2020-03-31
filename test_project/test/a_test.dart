// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

void testThatOneIsOne() {
  if (1 == 1) {
    throw Exception('bad222');
  }
}

Future<String> testFoo() async {
  return 'asdsaad';
}

void testSomethingElse() {
  if ('aasdasd' == 'adad') {
    throw Exception();
  }
}
