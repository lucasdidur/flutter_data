// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:build/build.dart';
import 'package:flutter_data/flutter_data.dart';
import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:glob/glob.dart';

import 'utils.dart';

Builder dataExtensionIntermediateBuilder(options) =>
    DataExtensionIntermediateBuilder();

class DataExtensionIntermediateBuilder implements Builder {
  @override
  final buildExtensions = const {
    '.dart': ['.info']
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final resolver = buildStep.resolver;
    if (!await resolver.isLibrary(buildStep.inputId)) return;
    final lib = LibraryReader(await buildStep.inputLibrary);

    final exportAnnotation = TypeChecker.fromRuntime(DataRepository);
    final annotated = [
      for (final member in lib.annotatedWith(exportAnnotation)) member.element,
    ];

    if (annotated.isNotEmpty) {
      await buildStep.writeAsString(
          buildStep.inputId.changeExtension('.info'),
          annotated.map((element) {
            return [
              DataHelpers.getType(element.name),
              (findTypesInRelationshipGraph(element as ClassElement).toList()
                    ..sort())
                  .join(','),
              element.location.components.first
            ].join('#');
          }).join(';'));
    }
  }
}

Builder dataExtensionBuilder(options) => DataExtensionBuilder();

class DataExtensionBuilder implements Builder {
  @override
  final buildExtensions = const {
    r'$lib$': ['main.data.dart']
  };

  @override
  Future<void> build(BuildStep b) async {
    final finalAssetId = AssetId(b.inputId.package, 'lib/main.data.dart');

    final _classes = [
      await for (final file in b.findAssets(Glob('**/*.info')))
        await b.readAsString(file)
    ];

    final classes = _classes.fold<List<Map<String, String>>>([], (acc, line) {
      for (final e in line.split(';')) {
        var parts = e.split('#');
        acc.add({
          'name': parts[0].singularize(),
          'related': parts[1],
          'path': parts[2]
        });
      }
      return acc;
    });

    // if this is a library, do not generate
    if (classes.any((c) => c['path'].startsWith('asset:'))) {
      return null;
    }

    final modelImports =
        classes.map((c) => 'import \'${c["path"]}\';').toSet().join('\n');

    var providerRegistration = '';

    final graphs = {
      for (final clazz in classes)
        if (clazz['related'].isNotEmpty)
          '\'${clazz['related']}\'': {
            for (final type in clazz['related'].split(','))
              '\'$type\'':
                  'ref.read(${type.singularize()}RemoteAdapterProvider)'
          }
    };

    // check dependencies

    final importPathProvider = await isDependency('path_provider', b);
    final importProvider = await isDependency('provider', b);
    final importGetIt = await isDependency('get_it', b);

    //
    var getItRegistration = '';

    if (importProvider) {
      providerRegistration = '''\n
List<SingleChildWidget> repositoryProviders({FutureFn<String> baseDirFn, List<int> encryptionKey,
    bool clear, bool remote, bool verbose, FutureFn alsoAwait}) {

  return [
    p.Provider(
        create: (_) => ProviderStateOwner(
          overrides: [
            configureRepositoryLocalStorage(
                baseDirFn: baseDirFn, encryptionKey: encryptionKey, clear: clear),
          ]
      ),
    ),
    p.FutureProvider<RepositoryInitializer>(
      create: (context) async {
        final init = await p.Provider.of<ProviderStateOwner>(context, listen: false).ref.read(repositoryInitializerProvider(remote: remote, verbose: verbose, alsoAwait: alsoAwait));
        internalLocatorFn = (provider, context) => provider.readOwner(
            p.Provider.of<ProviderStateOwner>(context, listen: false));
        return init;
      },
    ),''' +
          classes.map((c) => '''
    p.ProxyProvider<RepositoryInitializer, Repository<${(c['name']).capitalize()}>>(
      lazy: false,
      update: (context, i, __) => i == null ? null : p.Provider.of<ProviderStateOwner>(context, listen: false).ref.read(${c['name']}RepositoryProvider),
      dispose: (_, r) => r?.dispose(),
    ),''').join('\n') +
          ']; }';
    }

    if (importGetIt) {
      getItRegistration = '''
extension GetItFlutterDataX on GetIt {
  void registerRepositories({FutureFn<String> baseDirFn, List<int> encryptionKey,
    bool clear, bool remote, bool verbose}) {
final i = GetIt.instance;

final _owner = ProviderStateOwner(
  overrides: [
    configureRepositoryLocalStorage(baseDirFn: baseDirFn, encryptionKey: encryptionKey, clear: clear),
  ],
);

if (i.isRegistered<RepositoryInitializer>()) {
  return;
}

i.registerSingletonAsync<RepositoryInitializer>(() async {
    final init = _owner.ref.read(repositoryInitializerProvider(
          remote: remote, verbose: verbose));
    internalLocatorFn = (provider, _) => provider.readOwner(_owner);
    return init;
  });''' +
          classes.map((c) => '''
  
i.registerSingletonWithDependencies<Repository<${(c['name']).capitalize()}>>(
      () => _owner.ref.read(${c['name']}RepositoryProvider),
      dependsOn: [RepositoryInitializer]);

      ''').join('\n') +
          '} }';
    }

    final pathProviderImport = importPathProvider
        ? "import 'package:path_provider/path_provider.dart';"
        : '';

    final providerImports = importProvider
        ? [
            "import 'package:provider/provider.dart' as p;",
            "import 'package:provider/single_child_widget.dart';",
          ].join('\n')
        : '';

    final getItImport =
        importGetIt ? "import 'package:get_it/get_it.dart';" : '';

    final importFlutterRiverpod = await isDependency('flutter_riverpod', b) ||
        await isDependency('hooks_riverpod', b);

    final riverpodImport = importFlutterRiverpod
        ? "import 'package:flutter_riverpod/flutter_riverpod.dart';"
        : '';

    final internalLocator = importFlutterRiverpod
        ? '''
    internalLocatorFn = (provider, context) => provider.read(context);
    '''
        : '';

    //

    final repoEntries = classes.map((c) => '''
            await ref.read(${c['name']}RepositoryProvider).initialize(
              remote: args?.remote,
              verbose: args?.verbose,
              adapters: graphs['${c['related']}'],
              ref: ref,
            );''').join('');

    await b.writeAsString(finalAssetId, '''\n
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: directives_ordering, top_level_function_literal_block

import 'package:flutter_data/flutter_data.dart';

$pathProviderImport
$providerImports
$getItImport
$riverpodImport

$modelImports

Override configureRepositoryLocalStorage({FutureFn<String> baseDirFn, List<int> encryptionKey, bool clear}) {
  // ignore: unnecessary_statements
  baseDirFn${importPathProvider ? ' ??= () => getApplicationDocumentsDirectory().then((dir) => dir.path)' : ''};
  return hiveLocalStorageProvider.overrideAs(Provider(
        (_) => HiveLocalStorage(baseDirFn: baseDirFn, encryptionKey: encryptionKey, clear: clear)));
}

FutureProvider<RepositoryInitializer> repositoryInitializerProvider(
        {bool remote, bool verbose, FutureFn alsoAwait}) {
  $internalLocator
  return _repositoryInitializerProviderFamily(
      RepositoryInitializerArgs(remote, verbose, alsoAwait));
}

final _repositoryInitializerProviderFamily =
  FutureProvider.family<RepositoryInitializer, RepositoryInitializerArgs>((ref, args) async {
    final graphs = <String, Map<String, RemoteAdapter>>$graphs;
    $repoEntries
    if (args?.alsoAwait != null) {
      await args.alsoAwait();
    }
    return RepositoryInitializer();
});

$providerRegistration

$getItRegistration
''');
  }
}

Set<String> findTypesInRelationshipGraph(ClassElement elem,
    [Set<String> result]) {
  return relationshipFields(elem)
      .fold<Set<String>>(result ?? {DataHelpers.getType(elem.name)}, (acc, f) {
    var type = DataHelpers.getType(f.typeElement.name);
    if (!acc.contains(type)) {
      acc.add(type);
      acc.addAll(findTypesInRelationshipGraph(f.typeElement, acc));
    }
    return acc;
  });
}