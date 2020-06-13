// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:coverage/coverage.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:vm_service/vm_service.dart';

/// A service for measuring and merging coverage reports.
class CoverageService {
  CoverageService({
    this.fileSystem = const LocalFileSystem(),
    this.processManager = const LocalProcessManager(),
  });

  final FileSystem fileSystem;
  final ProcessManager processManager;
  Map<String, Map<int, int>> _globalHitmap;

  /// Output the collected coverage data into [coveragePath].
  ///
  /// This will flush all cached coverage data.
  Future<bool> writeCoverageData(
    String coveragePath, {
    @required String packagesPath,
  }) async {
    var coverageData = await _finalizeCoverage(
      packagesPath: packagesPath,
    );
    if (coverageData == null) {
      return false;
    }

    var coverageFile = fileSystem.file(coveragePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(coverageData, flush: true);

    var tempDir =
        fileSystem.systemTempDirectory.createTempSync('tester_coverage.');
    try {
      var sourceFile = coverageFile
          .copySync(fileSystem.path.join(tempDir.path, 'lcov.source.info'));
      var result = await processManager.run(<String>[
        'lcov',
        '--add-tracefile',
        coveragePath,
        '--add-tracefile',
        sourceFile.path,
        '--output-file',
        coverageFile.path,
      ]);
      if (result.exitCode != 0) {
        return false;
      }
    } finally {
      tempDir.deleteSync(recursive: true);
    }
    return true;
  }

  /// Collects coverage for an isolate using the given vm service.
  ///
  /// This should be called when the code whose coverage data is being collected
  /// has been run to completion so that all coverage data has been recorded.
  ///
  /// The returned [Future] completes when the coverage is collected.
  Future<void> collectCoverageIsolate(
    VmService service,
    bool Function(String) libraryPredicate,
    String packagesPath,
  ) async {
    var result = await _getAllCoverage(service, libraryPredicate);
    _addHitmap(await createHitmap(
      result['coverage'] as List<Map<String, dynamic>>,
      checkIgnoredLines: true,
      packagesPath: packagesPath,
    ));
  }

  void _addHitmap(Map<String, Map<int, int>> hitmap) {
    if (_globalHitmap == null) {
      _globalHitmap = hitmap;
    } else {
      mergeHitmaps(hitmap, _globalHitmap);
    }
  }

  /// Returns a future that will complete with the formatted coverage data
  /// (using [formatter]) once all coverage data has been collected.
  ///
  /// This will not start any collection tasks. It us up to the caller of to
  /// call [collectCoverage] for each process first.
  Future<String> _finalizeCoverage({
    @required String packagesPath,
  }) async {
    if (_globalHitmap == null) {
      return null;
    }
    var resolver = Resolver(packagesPath: packagesPath);
    var packagePath = fileSystem.currentDirectory.path;
    var formatter = LcovFormatter(
      resolver,
      reportOn: <String>[fileSystem.path.join(packagePath, 'lib')],
      basePath: packagePath,
    );
    var result = await formatter.format(_globalHitmap);
    _globalHitmap = null;
    return result;
  }

  Future<Map<String, dynamic>> _getAllCoverage(
      VmService service, bool Function(String) libraryPredicate) async {
    var vm = await service.getVM();
    var coverage = <Map<String, dynamic>>[];
    for (var isolateRef in vm.isolates) {
      Map<String, Object> scriptList;
      try {
        var actualScriptList = await service.getScripts(isolateRef.id);
        scriptList = actualScriptList.json;
      } on SentinelException {
        continue;
      }
      var futures = <Future<void>>[];
      var scripts = <String, Map<String, dynamic>>{};
      var sourceReports = <String, Map<String, dynamic>>{};
      // For each ScriptRef loaded into the VM, load the corresponding Script and
      // SourceReport object.

      for (var script in (scriptList['scripts'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        if (!libraryPredicate(script['uri'] as String)) {
          continue;
        }
        var scriptId = script['id'] as String;
        futures.add(service
            .getSourceReport(
          isolateRef.id,
          <String>['Coverage'],
          scriptId: scriptId,
          forceCompile: true,
        )
            .then((SourceReport report) {
          sourceReports[scriptId] = report.json;
        }));
        futures
            .add(service.getObject(isolateRef.id, scriptId).then((Obj script) {
          scripts[scriptId] = script.json;
        }));
      }
      await Future.wait(futures);
      _buildCoverageMap(scripts, sourceReports, coverage);
    }
    return <String, dynamic>{'type': 'CodeCoverage', 'coverage': coverage};
  }

  // Build a hitmap of Uri -> Line -> Hit Count for each script object.
  void _buildCoverageMap(
    Map<String, Map<String, dynamic>> scripts,
    Map<String, Map<String, dynamic>> sourceReports,
    List<Map<String, dynamic>> coverage,
  ) {
    var hitMaps = <String, Map<int, int>>{};
    for (var scriptId in scripts.keys) {
      var sourceReport = sourceReports[scriptId];
      for (var range in (sourceReport['ranges'] as List<dynamic>)
          .cast<Map<String, dynamic>>()) {
        var coverage = (range['coverage'] as Map).cast<String, Object>();
        // Coverage reports may sometimes be null for a Script.
        if (coverage == null) {
          continue;
        }
        var scriptRef = (sourceReport['scripts'][range['scriptIndex']] as Map)
            .cast<String, Object>();
        var uri = scriptRef['uri'] as String;

        hitMaps[uri] ??= <int, int>{};
        var hitMap = hitMaps[uri];
        var hits = (coverage['hits'] as List<dynamic>).cast<int>();
        var misses = (coverage['misses'] as List<dynamic>).cast<int>();
        var tokenPositions =
            scripts[scriptRef['id']]['tokenPosTable'] as List<dynamic>;
        // The token positions can be null if the script has no coverable lines.
        if (tokenPositions == null) {
          continue;
        }
        if (hits != null) {
          for (var hit in hits) {
            var line = _lineAndColumn(hit, tokenPositions)[0];
            var current = hitMap[line] ?? 0;
            hitMap[line] = current + 1;
          }
        }
        if (misses != null) {
          for (var miss in misses) {
            var line = _lineAndColumn(miss, tokenPositions)[0];
            hitMap[line] ??= 0;
          }
        }
      }
    }
    hitMaps.forEach((String uri, Map<int, int> hitMap) {
      coverage.add(_toScriptCoverageJson(uri, hitMap));
    });
  }

  /// Binary search the token position table for the line and column which
  /// corresponds to each token position.
  /// The format of this table is described in https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  List<int> _lineAndColumn(int position, List<dynamic> tokenPositions) {
    var min = 0;
    var max = tokenPositions.length;
    while (min < max) {
      var mid = min + ((max - min) >> 1);
      var row = (tokenPositions[mid] as List<dynamic>).cast<int>();
      if (row[1] > position) {
        max = mid;
      } else {
        for (var i = 1; i < row.length; i += 2) {
          if (row[i] == position) {
            return <int>[row.first, row[i + 1]];
          }
        }
        min = mid + 1;
      }
    }
    throw StateError('Unreachable');
  }

  // Returns a JSON hit map backward-compatible with pre-1.16.0 SDKs.
  Map<String, dynamic> _toScriptCoverageJson(
      String scriptUri, Map<int, int> hitMap) {
    var json = <String, dynamic>{};
    var hits = <int>[];
    hitMap.forEach((int line, int hitCount) {
      hits.add(line);
      hits.add(hitCount);
    });
    json['source'] = scriptUri;
    json['script'] = <String, dynamic>{
      'type': '@Script',
      'fixedId': true,
      'id': 'libraries/1/scripts/${Uri.encodeComponent(scriptUri)}',
      'uri': scriptUri,
      '_kind': 'library',
    };
    json['hits'] = hits;
    return json;
  }
}
