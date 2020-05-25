// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Tests that a sync function completes normally
void testNoException() {}

/// Tests that a sync function that returns an object completes normally.
Object testReturnObject() {
  return Object();
}

/// Tests that a sync exception causes a test failure.
void testSyncException() {
  throw Exception('Expected 1 == 2 but was false.');
}

/// Tests that a sync error causes a test failure.
void testSyncError() {
  throw Error();
}

/// Tests that a sync function that throws an object causes a test failure.
void testSyncThrownObject() {
  throw Object();
}

/// Tests that an async function with no errors completes successfully.
Future<void> testAsyncNoException() async {
  await null;
}

/// Tests that assn async function that returns an object completes successfully.
Future<Object> testAsyncReturnValues() async {
  await null;
  return Object();
}

/// Tests that an async function that completes with an exception causes a test
/// failure.
Future<void> testAsyncException() async {
  await null;
  throw Exception();
}

/// Tests that an async function that completes with an error causes a test
/// failure.
Future<void> testAsyncError() async {
  await null;
  throw Error();
}
