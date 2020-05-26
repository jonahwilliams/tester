# tester

<img width="543" alt="Screen Shot 2020-05-25 at 6 46 18 PM" src="https://user-images.githubusercontent.com/8975114/82852611-3cd53c00-9eb8-11ea-8f37-3831d1d84f34.png">

An experimental test runner with no runtime dependencies. Precompiled binaries for windows, linux, and macOS can be found in the releases tab.

This should be run from the root of a dart project containing `pubspec.yaml`. By default, it will run all files in `test/` ending in `_test.dart`. It also accepts multiple positional arguments.

```
macos_tester

// Or

macos_tester test/a_test.dart test/b_test.dart
```

Currently this runner can execute Dart, Dart Web, Flutter, and Flutter Web tests. This requires the Flutter SDK to be on the path. Running Web or Flutter Web tests requires Chrome to be available, and Flutter Web additionally requires that web is enabled in the Flutter SDK with:


```
flutter config --enable-web
```

By default, tester runs all tests and then exits. It can also be configured with `--watch`, and will rerun any updated tests and stay resident.
