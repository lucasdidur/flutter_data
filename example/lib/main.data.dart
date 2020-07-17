

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: directives_ordering, top_level_function_literal_block

import 'package:flutter_data/flutter_data.dart';



import 'package:get_it/get_it.dart';

import 'package:jsonplaceholder_example/models/post.dart';
import 'package:jsonplaceholder_example/models/user.dart';
import 'package:jsonplaceholder_example/models/comment.dart';

Override configureRepositoryLocalStorage({FutureFn<String> baseDirFn, List<int> encryptionKey, bool clear}) {
  // ignore: unnecessary_statements
  baseDirFn;
  return hiveLocalStorageProvider.overrideAs(Provider(
        (_) => HiveLocalStorage(baseDirFn: baseDirFn, encryptionKey: encryptionKey, clear: clear)));
}

FutureProvider<RepositoryInitializer> repositoryInitializerProvider(
        {bool remote, bool verbose, FutureFn alsoAwait}) =>
    _repositoryInitializerProviderFamily(
        RepositoryInitializerArgs(remote, verbose, alsoAwait));

final _repositoryInitializerProviderFamily =
  FutureProvider.family<RepositoryInitializer, RepositoryInitializerArgs>((ref, args) async {
    final graphs = <String, Map<String, RemoteAdapter>>{'comments,posts,users': {'comments': ref.read(commentsRemoteAdapterProvider), 'posts': ref.read(postsRemoteAdapterProvider), 'users': ref.read(usersRemoteAdapterProvider)}, 'users': {'users': ref.read(usersRemoteAdapterProvider)}};
                await ref.read(postsRepositoryProvider).initialize(
              remote: args?.remote,
              verbose: args?.verbose,
              adapters: graphs['comments,posts,users'],
              ref: ref,
            );            await ref.read(usersRepositoryProvider).initialize(
              remote: args?.remote,
              verbose: args?.verbose,
              adapters: graphs['users'],
              ref: ref,
            );            await ref.read(commentsRepositoryProvider).initialize(
              remote: args?.remote,
              verbose: args?.verbose,
              adapters: graphs['comments,posts,users'],
              ref: ref,
            );
    if (args?.alsoAwait != null) {
      await args.alsoAwait();
    }
    return RepositoryInitializer();
});



extension GetItFlutterDataX on GetIt {
  void registerRepositories({FutureFn<String> baseDirFn, List<int> encryptionKey,
    bool clear, bool remote, bool verbose}) {
final i = debugGlobalServiceLocatorInstance = GetIt.instance;

final _owner = ProviderStateOwner(
  overrides: [
    configureRepositoryLocalStorage(baseDirFn: baseDirFn, encryptionKey: encryptionKey, clear: clear),
  ],
);

i.registerSingletonAsync<RepositoryInitializer>(() async {
    return _owner.ref.read(repositoryInitializerProvider(
          remote: remote, verbose: verbose));
  });  
i.registerSingletonWithDependencies<Repository<Post>>(
      () => _owner.ref.read(postsRepositoryProvider),
      dependsOn: [RepositoryInitializer]);

      
  
i.registerSingletonWithDependencies<Repository<User>>(
      () => _owner.ref.read(usersRepositoryProvider),
      dependsOn: [RepositoryInitializer]);

      
  
i.registerSingletonWithDependencies<Repository<Comment>>(
      () => _owner.ref.read(commentsRepositoryProvider),
      dependsOn: [RepositoryInitializer]);

      } }
