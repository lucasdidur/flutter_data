import 'dart:async';

import 'package:flutter_data/flutter_data.dart';

class HiveLocalStorage {
  HiveLocalStorage({
    this.baseDirFn,
    this.encryptionKey,
    LocalStorageClearStrategy? clear,
  }) : clear = clear ?? LocalStorageClearStrategy.never;

  final String? encryptionKey;
  final FutureOr<String> Function()? baseDirFn;
  final LocalStorageClearStrategy clear;
  late final String path;

  var isInitialized = false;

  Future<void> initialize() async {
    if (isInitialized) return;

    if (baseDirFn == null) {
      throw UnsupportedError('''
A base directory path MUST be supplied to
the hiveLocalStorageProvider via the `baseDirFn`
callback.

In Flutter, `baseDirFn` will be supplied automatically if
the `path_provider` package is in `pubspec.yaml` AND
Flutter Data is properly configured:

Did you supply the override?

Widget build(context) {
  return ProviderContainer(
    overrides: [
      configureRepositoryLocalStorage()
    ],
    child: MaterialApp(
''');
    }
    path = await baseDirFn!();
    isInitialized = true;
  }

  Future<void> destroy() async {
    // TODO restore Hive features here?
    // Hive.deleteAllBoxesFromDisk();
  }
}

enum LocalStorageClearStrategy {
  always,
  never,
  whenError,
}

final hiveLocalStorageProvider = Provider<HiveLocalStorage>(
  (ref) => HiveLocalStorage(baseDirFn: () => ''),
);
