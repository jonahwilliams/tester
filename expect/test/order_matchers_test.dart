// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';
import 'test_utils.dart';

testGreaterThan() {
  shouldPass(10, greaterThan(9));
  shouldFail(
      9,
      greaterThan(10),
      'Expected: a value greater than <10> '
      'Actual: <9> '
      'Which: is not a value greater than <10>');
}

testGreaterThanOrEqualTo() {
  shouldPass(10, greaterThanOrEqualTo(10));
  shouldFail(
      9,
      greaterThanOrEqualTo(10),
      'Expected: a value greater than or equal to <10> '
      'Actual: <9> '
      'Which: is not a value greater than or equal to <10>');
}

testLessThan() {
  shouldFail(
      10,
      lessThan(9),
      'Expected: a value less than <9> '
      'Actual: <10> '
      'Which: is not a value less than <9>');
  shouldPass(9, lessThan(10));
}

testLessThanOrEqualTo() {
  shouldPass(10, lessThanOrEqualTo(10));
  shouldFail(
      11,
      lessThanOrEqualTo(10),
      'Expected: a value less than or equal to <10> '
      'Actual: <11> '
      'Which: is not a value less than or equal to <10>');
}

testIsZero() {
  shouldPass(0, isZero);
  shouldFail(
      1,
      isZero,
      'Expected: a value equal to <0> '
      'Actual: <1> '
      'Which: is not a value equal to <0>');
}

testIsNonZero() {
  shouldFail(
      0,
      isNonZero,
      'Expected: a value not equal to <0> '
      'Actual: <0> '
      'Which: is not a value not equal to <0>');
  shouldPass(1, isNonZero);
}

testIsPositive() {
  shouldFail(
      -1,
      isPositive,
      'Expected: a positive value '
      'Actual: <-1> '
      'Which: is not a positive value');
  shouldFail(
      0,
      isPositive,
      'Expected: a positive value '
      'Actual: <0> '
      'Which: is not a positive value');
  shouldPass(1, isPositive);
}

testIsNegative() {
  shouldPass(-1, isNegative);
  shouldFail(
      0,
      isNegative,
      'Expected: a negative value '
      'Actual: <0> '
      'Which: is not a negative value');
}

testIsNonPositive() {
  shouldPass(-1, isNonPositive);
  shouldPass(0, isNonPositive);
  shouldFail(
      1,
      isNonPositive,
      'Expected: a non-positive value '
      'Actual: <1> '
      'Which: is not a non-positive value');
}

testIsNonNegative() {
  shouldPass(1, isNonNegative);
  shouldPass(0, isNonNegative);
  shouldFail(
      -1,
      isNonNegative,
      'Expected: a non-negative value '
      'Actual: <-1> '
      'Which: is not a non-negative value');
}

testGreaterThanNaN() {
  shouldFail(
      double.nan,
      greaterThan(10),
      'Expected: a value greater than <10> '
      'Actual: <NaN> '
      'Which: is not a value greater than <10>');
  shouldFail(
      10,
      greaterThan(double.nan),
      'Expected: a value greater than <NaN> '
      'Actual: <10> '
      'Which: is not a value greater than <NaN>');
}

testLessThanOrEqualToNaN() {
  shouldFail(
      double.nan,
      lessThanOrEqualTo(10),
      'Expected: a value less than or equal to <10> '
      'Actual: <NaN> '
      'Which: is not a value less than or equal to <10>');
  shouldFail(
      10,
      lessThanOrEqualTo(double.nan),
      'Expected: a value less than or equal to <NaN> '
      'Actual: <10> '
      'Which: is not a value less than or equal to <NaN>');
}
