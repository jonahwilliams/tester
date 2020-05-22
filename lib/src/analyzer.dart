// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// An abstraction layer over the analyzer API.
class Analyzer {
  const Analyzer();

  /// Collect all top-level methods that begin with 'test'.
  List<String> collectTestNames(String testFilePath) {
    var result = parseFile(
        path: testFilePath, featureSet: FeatureSet.fromEnableFlags(<String>[]));
    var testNames = <String>[];
    for (var member in result.unit.declarations) {
      if (member is FunctionDeclaration) {
        var name = member.name.toString();
        if (name.startsWith('test')) {
          testNames.add(name);
        }
      }
    }
    return testNames;
  }
}
