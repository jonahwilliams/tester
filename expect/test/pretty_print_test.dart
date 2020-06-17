// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:expect/src/pretty_print.dart';
import 'package:expect/expect.dart';

class DefaultToString {}

class CustomToString {
  @override
  String toString() => 'string representation';
}

class _PrivateName {
  @override
  String toString() => 'string representation';
}

class _PrivateNameIterable extends IterableMixin {
  @override
  Iterator get iterator => [1, 2, 3].iterator;
}

testPrimitiveObjects() {
  expect(prettyPrint(12), equals('<12>'));
  expect(prettyPrint(12.13), equals('<12.13>'));
  expect(prettyPrint(true), equals('<true>'));
  expect(prettyPrint(null), equals('<null>'));
  expect(prettyPrint(() => 12), matches(r'<Closure.*>'));
}

testStringAscii() {
  expect(prettyPrint('foo'), equals("'foo'"));
}

testStringNewlines() {
  expect(
      prettyPrint('foo\nbar\nbaz'),
      equals("'foo\\n'\n"
          "  'bar\\n'\n"
          "  'baz'"));
}

testStringControlCharacters() {
  expect(prettyPrint("foo\rbar\tbaz'qux\v"), equals(r"'foo\rbar\tbaz\'qux\v'"));
}

testSimpleIterable() {
  expect(prettyPrint([1, true, 'foo']), equals("[1, true, 'foo']"));
}

testMultilineString() {
  expect(
      prettyPrint(['foo', 'bar\nbaz\nbip', 'qux']),
      equals('[\n'
          "  'foo',\n"
          "  'bar\\n'\n"
          "    'baz\\n'\n"
          "    'bip',\n"
          "  'qux'\n"
          ']'));
}

testContainsMatcher() {
  expect(prettyPrint(['foo', endsWith('qux')]),
      equals("['foo', <a string ending with 'qux'>]"));
}

testUnderMaxLineLength() {
  expect(prettyPrint([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], maxLineLength: 30),
      equals('[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]'));
}

testOverMaxLineLength() {
  expect(
      prettyPrint([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], maxLineLength: 29),
      equals('[\n'
          '  0,\n'
          '  1,\n'
          '  2,\n'
          '  3,\n'
          '  4,\n'
          '  5,\n'
          '  6,\n'
          '  7,\n'
          '  8,\n'
          '  9\n'
          ']'));
}

testFactorsIndentationIntoMaxLineLength() {
  expect(
      prettyPrint([
        'foo\nbar',
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      ], maxLineLength: 30),
      equals('[\n'
          "  'foo\\n'\n"
          "    'bar',\n"
          '  [\n'
          '    0,\n'
          '    1,\n'
          '    2,\n'
          '    3,\n'
          '    4,\n'
          '    5,\n'
          '    6,\n'
          '    7,\n'
          '    8,\n'
          '    9\n'
          '  ]\n'
          ']'));
}

testUnderMaxItems() {
  expect(prettyPrint([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], maxItems: 10),
      equals('[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]'));
}

testOverMaxItems() {
  expect(prettyPrint([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], maxItems: 9),
      equals('[0, 1, 2, 3, 4, 5, 6, 7, ...]'));
}

testRecursive() {
  var list = <dynamic>[1, 2, 3];
  list.add(list);
  expect(prettyPrint(list), equals('[1, 2, 3, (recursive)]'));
}

testMapWithSimpleObjects() {
  expect(
      prettyPrint({'foo': 1, 'bar': true}), equals("{'foo': 1, 'bar': true}"));
}

testMapWithMultilineString() {
  expect(
      prettyPrint({'foo\nbar': 1, 'bar': true}),
      equals('{\n'
          "  'foo\\n'\n"
          "    'bar': 1,\n"
          "  'bar': true\n"
          '}'));
}

testMapWithMultilineStringValue() {
  expect(
      prettyPrint({'foo': 'bar\nbaz', 'qux': true}),
      equals('{\n'
          "  'foo': 'bar\\n'\n"
          "    'baz',\n"
          "  'qux': true\n"
          '}'));
}

testMapWithMulilineStringKeyValue() {
  expect(
      prettyPrint({'foo\nbar': 'baz\nqux'}),
      equals('{\n'
          "  'foo\\n'\n"
          "    'bar': 'baz\\n'\n"
          "    'qux'\n"
          '}'));
}

testMapWithMatcherKey() {
  expect(prettyPrint({endsWith('bar'): 'qux'}),
      equals("{<a string ending with 'bar'>: 'qux'}"));
}

testMapWithMatcherValue() {
  expect(prettyPrint({'foo': endsWith('qux')}),
      equals("{'foo': <a string ending with 'qux'>}"));
}

testMapUnderMaxLineLength() {
  expect(prettyPrint({'0': 1, '2': 3, '4': 5, '6': 7}, maxLineLength: 32),
      equals("{'0': 1, '2': 3, '4': 5, '6': 7}"));
}

testMapOverMaxLineLength() {
  expect(
      prettyPrint({'0': 1, '2': 3, '4': 5, '6': 7}, maxLineLength: 31),
      equals('{\n'
          "  '0': 1,\n"
          "  '2': 3,\n"
          "  '4': 5,\n"
          "  '6': 7\n"
          '}'));
}

testMapMaxLineLengthWithIndent() {
  expect(
      prettyPrint([
        'foo\nbar',
        {'0': 1, '2': 3, '4': 5, '6': 7}
      ], maxLineLength: 32),
      equals('[\n'
          "  'foo\\n'\n"
          "    'bar',\n"
          '  {\n'
          "    '0': 1,\n"
          "    '2': 3,\n"
          "    '4': 5,\n"
          "    '6': 7\n"
          '  }\n'
          ']'));
}

testMapUnderMaxItems() {
  expect(prettyPrint({'0': 1, '2': 3, '4': 5, '6': 7}, maxItems: 4),
      equals("{'0': 1, '2': 3, '4': 5, '6': 7}"));
}

testMapOverMaxItems() {
  expect(prettyPrint({'0': 1, '2': 3, '4': 5, '6': 7}, maxItems: 3),
      equals("{'0': 1, '2': 3, ...}"));
}

testObjectToString() {
  expect(prettyPrint(DefaultToString()),
      equals("<Instance of 'DefaultToString'>"));
}

testImplementedToString() {
  expect(prettyPrint(CustomToString()),
      equals('CustomToString:<string representation>'));
}

testWithPrivateAndToStrng() {
  expect(prettyPrint(_PrivateName()),
      equals('_PrivateName:<string representation>'));
}

testIterable() {
  expect(prettyPrint([1, 2, 3, 4].map((n) => n * 2)),
      equals('MappedListIterable<int, int>:[2, 4, 6, 8]'));
}

testIterableWithPrivate() {
  expect(prettyPrint(_PrivateNameIterable()),
      equals('_PrivateNameIterable:[1, 2, 3]'));
}

testRuntimeType() {
  expect(prettyPrint(''.runtimeType), 'Type:<String>');
}

testType() {
  expect(prettyPrint(String), 'Type:<String>');
}
