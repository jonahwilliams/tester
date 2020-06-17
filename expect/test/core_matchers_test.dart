// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';
import 'test_utils.dart';

testIsTrue() {
  shouldPass(true, isTrue);
  shouldFail(false, isTrue, 'Expected: true Actual: <false>');
}

testIsFalse() {
  shouldPass(false, isFalse);
  shouldFail(10, isFalse, 'Expected: false Actual: <10>');
  shouldFail(true, isFalse, 'Expected: false Actual: <true>');
}

testIsNull() {
  shouldPass(null, isNull);
  shouldFail(false, isNull, 'Expected: null Actual: <false>');
}

testIsNotNull() {
  shouldPass(false, isNotNull);
  shouldFail(null, isNotNull, 'Expected: not null Actual: <null>');
}

testIsNaN() {
  shouldPass(double.nan, isNaN);
  shouldFail(3.1, isNaN, 'Expected: NaN Actual: <3.1>');
  shouldFail('not a num', isNaN, endsWith('not an <Instance of \'num\'>'));
}

testIsNotNaN() {
  shouldPass(3.1, isNotNaN);
  shouldFail(double.nan, isNotNaN, 'Expected: not NaN Actual: <NaN>');
  shouldFail('not a num', isNotNaN, endsWith('not an <Instance of \'num\'>'));
}

testSame() {
  var a = {};
  var b = {};
  shouldPass(a, same(a));
  shouldFail(b, same(a), 'Expected: same instance as {} Actual: {}');
}

testEquals() {
  var a = {};
  var b = {};
  shouldPass(a, equals(a));
  shouldPass(a, equals(b));
}

testEqualsWithNull() {
  Object a; // null
  var b = {};
  shouldPass(a, equals(a));
  shouldFail(a, equals(b), 'Expected: {} Actual: <null> Which: expected a map');
  shouldFail(b, equals(a), 'Expected: <null> Actual: {}');
}

testEqualsWithASet() {
  var numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  var set1 = numbers.toSet();
  numbers.shuffle();
  var set2 = numbers.toSet();

  shouldPass(set2, equals(set1));
  shouldPass(numbers, equals(set1));
  shouldFail(
      [1, 2, 3, 4, 5, 6, 7, 8, 9],
      equals(set1),
      matches(r'Expected: .*:\[1, 2, 3, 4, 5, 6, 7, 8, 9, 10\]'
          r'  Actual: \[1, 2, 3, 4, 5, 6, 7, 8, 9\]'
          r'   Which: does not contain 10'));
  shouldFail(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
      equals(set1),
      matches(r'Expected: .*:\[1, 2, 3, 4, 5, 6, 7, 8, 9, 10\]'
          r'  Actual: \[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11\]'
          r'   Which: larger than expected'));
}

testAnything() {
  var a = {};
  shouldPass(0, anything);
  shouldPass(null, anything);
  shouldPass(a, anything);
  shouldFail(a, isNot(anything), 'Expected: not anything Actual: {}');
}

testReturnsNormally() {
  shouldPass(doesNotThrow, returnsNormally);
  shouldFail(
      doesThrow,
      returnsNormally,
      matches(r'Expected: return normally'
          r'  Actual: <Closure.*>'
          r'   Which: threw StateError:<Bad state: X>'));
  shouldFail('not a function', returnsNormally,
      contains('not an <Instance of \'Function\'>'));
}

testHasLength() {
  var a = {};
  var b = [];
  shouldPass(a, hasLength(0));
  shouldPass(b, hasLength(0));
  shouldPass('a', hasLength(1));
  shouldFail(
      0,
      hasLength(0),
      'Expected: an object with length of <0> '
      'Actual: <0> '
      'Which: has no length property');

  b.add(0);
  shouldPass(b, hasLength(1));
  shouldFail(
      b,
      hasLength(2),
      'Expected: an object with length of <2> '
      'Actual: [0] '
      'Which: has length of <1>');

  b.add(0);
  shouldFail(
      b,
      hasLength(1),
      'Expected: an object with length of <1> '
      'Actual: [0, 0] '
      'Which: has length of <2>');
  shouldPass(b, hasLength(2));
}

testScalarTypeMismatch() {
  shouldFail(
      'error',
      equals(5.1),
      'Expected: <5.1> '
          "Actual: 'error'");
}

testNestedTypeMismatch() {
  shouldFail(
      ['error'],
      equals([5.1]),
      'Expected: [5.1] '
      "Actual: ['error'] "
      "Which: was 'error' instead of <5.1> at location [0]");
}

testIsInstanceOf() {
  shouldFail(0, predicate((x) => x is String, 'an instance of String'),
      'Expected: an instance of String Actual: <0>');
  shouldPass('cow', predicate((x) => x is String, 'an instance of String'));
  shouldFail(0, predicate((bool x) => x, 'bool value is true'),
      endsWith("not an <Instance of \'bool\'>"));
}

testDoublyNestedTypeMismatch() {
  shouldFail(
      [
        ['error']
      ],
      equals([
        [5.1]
      ]),
      'Expected: [[5.1]] '
      "Actual: [['error']] "
      "Which: was 'error' instead of <5.1> at location [0][0]");
}

testDoublyNestedInequality() {
  var actual1 = [
    ['foo', 'bar'],
    ['foo'],
    3,
    []
  ];
  var expected1 = [
    ['foo', 'bar'],
    ['foo'],
    4,
    []
  ];
  var reason1 = "Expected: [['foo', 'bar'], ['foo'], 4, []] "
      "Actual: [['foo', 'bar'], ['foo'], 3, []] "
      'Which: was <3> instead of <4> at location [2]';

  var actual2 = [
    ['foo', 'barry'],
    ['foo'],
    4,
    []
  ];
  var expected2 = [
    ['foo', 'bar'],
    ['foo'],
    4,
    []
  ];
  var reason2 = "Expected: [['foo', 'bar'], ['foo'], 4, []] "
      "Actual: [['foo', 'barry'], ['foo'], 4, []] "
      "Which: was 'barry' instead of 'bar' at location [0][1]";

  var actual3 = [
    ['foo', 'bar'],
    ['foo'],
    4,
    {'foo': 'bar'}
  ];
  var expected3 = [
    ['foo', 'bar'],
    ['foo'],
    4,
    {'foo': 'barry'}
  ];
  var reason3 = "Expected: [['foo', 'bar'], ['foo'], 4, {'foo': 'barry'}] "
      "Actual: [['foo', 'bar'], ['foo'], 4, {'foo': 'bar'}] "
      "Which: was 'bar' instead of 'barry' at location [3]['foo']";

  shouldFail(actual1, equals(expected1), reason1);
  shouldFail(actual2, equals(expected2), reason2);
  shouldFail(actual3, equals(expected3), reason3);
}
