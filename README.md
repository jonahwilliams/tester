# tester

<img width="650" src="https://user-images.githubusercontent.com/8975114/83311624-9b562f00-a1c4-11ea-9716-92cd3c455b9e.PNG">


An experimental test runner, designed for fast incremental test processing workflows and maximum flexibility due to a lack of significant runtime. Currently supports running tests on the Dart VM & Flutter, and within the Chrome browser it can run both Dart Web and Flutter for Web tests. Requires a version of the Flutter SDK that is extremely close to ToT to be present on the PATH, or configured via `FLUTTER_ROOT`.

## setup

Tester works best when `tester/bin` is added to your PATH environment variable. The tool itself will self-snapshot, but does not yet support any auto-update functionality.

## Running tests

tester should be run from the project root, the directory containing `pubspec.yaml`. By default, it will run all files in `test/` ending in `_test.dart` once and exit. It also accepts multiple positional arguments for one or more individual test files.

```
tester test/a_test.dart test/b_test.dart
```

The tester can also be started in a resident process that re-runs when test files or library sources are changed.

```
tester --watch
```

### Test Concurrency

tester runs each test in serial. In batch mode, multiple runners can be configured using `--concurrency/-j`. Increasing this number above 1 (the default) will slow down startup times, but may be faster for large numbers of tests.

```
tester -j4
```

### Test Platforms

The test platform (Dart VM, Flutter, Web, Flutter Web) can be configured using `--platform`. Web platforms require a chrome executable to be available.

```
tester --platform=dart test/dart_test.dart
tester --platform=flutter test/flutter_test.dart
```


### Coverage

Code coverage can be measured by passing --coverage (batch-mode only for now). This
is currently only supported on dart and flutter platforms, and not web or flutter_web.
