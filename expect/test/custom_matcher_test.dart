// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

import 'test_utils.dart';

class _BadCustomMatcher extends CustomMatcher {
  _BadCustomMatcher() : super('feature', 'description', {1: 'a'});
  @override
  Object featureValueOf(actual) => throw Exception('bang');
}

class _HasPrice extends CustomMatcher {
  _HasPrice(matcher) : super('Widget with a price that is', 'price', matcher);
  @override
  Object featureValueOf(actual) => (actual as Widget).price;
}

testFeatureMatcher() {
  var w = Widget();
  w.price = 10;
  shouldPass(w, _HasPrice(10));
  shouldPass(w, _HasPrice(greaterThan(0)));
  shouldFail(
      w,
      _HasPrice(greaterThan(10)),
      'Expected: Widget with a price that is a value greater than <10> '
      "Actual: <Instance of 'Widget'> "
      'Which: has price with value <10> which is not '
      'a value greater than <10>');
}

testCustomMatcherException() {
  shouldFail(
      'a',
      _BadCustomMatcher(),
      allOf([
        contains("Expected: feature {1: 'a'} "),
        contains("Actual: 'a' "),
        contains("Which: threw 'Exception: bang'"),
      ]));
}
