// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8

import 'dart:convert';

import 'package:expect/expect.dart';
import 'package:file/memory.dart';
import 'package:tester/src/test_info.dart';

void testLoadsFromCacheMissing() {
  var fileSystem = MemoryFileSystem.test();
  var infoProvider = TestInformationProvider(
      fileSystem: fileSystem,
      testCompatMode: true,
      packagesRootPath: '',
      testManifestPath: 'manifest.json');

  infoProvider.loadTestInfos();

  expect(infoProvider.cachedData, isEmpty);
}

void testLoadsFromCacheVersionMismatch() {
  var fileSystem = MemoryFileSystem.test();
  var infoProvider = TestInformationProvider(
      fileSystem: fileSystem,
      testCompatMode: true,
      packagesRootPath: '',
      testManifestPath: 'manifest.json');
  fileSystem.file('manifest.json').writeAsStringSync(json.encode({
        'v': 1232132,
      }));

  infoProvider.loadTestInfos();

  expect(infoProvider.cachedData, isEmpty);
  expect(fileSystem.file('manifest.json').existsSync(), false);
}

void testLoadsFromCacheTypeError() {
  var fileSystem = MemoryFileSystem.test();
  var infoProvider = TestInformationProvider(
      fileSystem: fileSystem,
      testCompatMode: true,
      packagesRootPath: '',
      testManifestPath: 'manifest.json');
  fileSystem
      .file('manifest.json')
      .writeAsStringSync(json.encode({'v': 1, 'f': 'asd'}));

  infoProvider.loadTestInfos();

  expect(infoProvider.cachedData, isEmpty);
  expect(fileSystem.file('manifest.json').existsSync(), false);
}

void testLoadsFromCacheNotUpToDate() {
  var fileSystem = MemoryFileSystem.test();
  var infoProvider = TestInformationProvider(
      fileSystem: fileSystem,
      testCompatMode: true,
      packagesRootPath: '',
      testManifestPath: 'manifest.json');
  fileSystem.file('test/example_test.dart')..createSync(recursive: true);
  fileSystem.file('manifest.json').writeAsStringSync(json.encode({
        'v': 1,
        'f': [
          {
            's': '2020-06-16T18:54:55.000',
            'u': 'file:///test/example_test.dart',
            'ds': [
              {
                'n': 'testExample',
                'd': 'description',
                'u': 'test/example_test.dart',
                's': 'org-dartlang-app:///test/example_test.dart',
                'l': 399,
                'c': null,
                'ct': false
              }
            ]
          }
        ]
      }));

  infoProvider.loadTestInfos();

  expect(infoProvider.cachedData, isEmpty);
  expect(fileSystem.file('manifest.json').existsSync(), true);
}

void testLoadsFromCacheUpToDate() {
  var fileSystem = MemoryFileSystem.test();
  var infoProvider = TestInformationProvider(
      fileSystem: fileSystem,
      testCompatMode: true,
      packagesRootPath: '',
      testManifestPath: 'manifest.json');
  var exampleFile = fileSystem.file('test/example_test.dart')
    ..createSync(recursive: true)
    ..lastModifiedSync();
  fileSystem.file('manifest.json').writeAsStringSync(json.encode({
        'v': 1,
        'f': [
          {
            's': exampleFile.lastModifiedSync().toIso8601String(),
            'u': 'file:///test/example_test.dart',
            'ds': [
              {
                'n': 'testExample',
                'd': 'description',
                'u': 'test/example_test.dart',
                's': 'org-dartlang-app:///test/example_test.dart',
                'l': 399,
                'c': null,
                'ct': false
              }
            ]
          }
        ]
      }));

  infoProvider.loadTestInfos();

  var testInfo = infoProvider.cachedData[Uri.parse('file:///test/example_test.dart')];
  expect(testInfo, isNotNull);
  expect(testInfo.single.name, 'testExample');
  expect(infoProvider.cachedStats[Uri.parse('file:///test/example_test.dart')],
      exampleFile.lastModifiedSync());
  expect(fileSystem.file('manifest.json').existsSync(), true);
}
