part of flutter_data;

/// An adapter base class for all operations for type [T].
///
/// Includes:
///
///  - Remote methods such as [_RemoteAdapter.findAll] or [_RemoteAdapter.save]
///  - Configuration methods and getters like [_RemoteAdapter.baseUrl] or [_RemoteAdapter.urlForFindAll]
///  - Serialization methods like [_SerializationAdapter.serializeAsync]
///  - Watch methods such as [_WatchAdapter.watchOneNotifier]
///  - Access to the [_BaseAdapter.core] for subclasses or mixins
///
/// This class is meant to be extended via mixing in new adapters.
/// This can be done with the [DataAdapter] annotation on a [DataModelMixin] class:
///
/// ```
/// @JsonSerializable()
/// @DataAdapter([MyAppAdapter])
/// class Todo with DataModel<Todo> {
///   @override
///   final int? id;
///   final String title;
///   final bool completed;
///
///   Todo({this.id, required this.title, this.completed = false});
/// }
/// ```
///
/// Identity in this layer is enforced by IDs.
// ignore: library_private_types_in_public_api
class Adapter<T extends DataModelMixin<T>> = _BaseAdapter<T>
    with _SerializationAdapter<T>, _RemoteAdapter<T>, _WatchAdapter<T>;

abstract class _BaseAdapter<T extends DataModelMixin<T>> with _Lifecycle {
  @protected
  _BaseAdapter(Ref ref, [this._internalHolder])
      : core = ref.read(_coreNotifierProvider),
        storage = ref.read(localStorageProvider);

  @protected
  @visibleForTesting
  final CoreNotifier core;

  @protected
  @visibleForTesting
  final LocalStorage storage;

  bool _stopInitialization = false;

  // None of these fields below can be late finals as they might be re-initialized
  Map<String, Adapter>? _adapters;
  bool? _remote;
  Ref? _ref;

  /// All adapters for the relationship subgraph of [T] and their relationships.
  ///
  /// This [Map] is typically required when initializing new models, and passed as-is.
  @protected
  @nonVirtual
  Map<String, Adapter> get adapters => _adapters!;

  /// Give access to the dependency injection system
  @nonVirtual
  Ref get ref => _ref!;

  /// INTERNAL: DO NOT USE
  @visibleForTesting
  @protected
  @nonVirtual
  String get internalType => DataHelpers.getInternalType<T>();

  /// The pluralized and downcased [DataHelpers.getType<T>] version of type [T]
  /// by default.
  ///
  /// Example: [T] as `Post` has a [type] of `posts`.
  String get type => internalType;

  /// ONLY FOR FLUTTER DATA INTERNAL USE
  Watcher? internalWatch;
  final InternalHolder<T>? _internalHolder;

  /// Set log level.
  // ignore: prefer_final_fields
  int logLevel = 0;

  // lifecycle methods

  @override
  var isInitialized = false;

  @mustCallSuper
  Future<void> onInitialized() async {}

  @mustCallSuper
  @nonVirtual
  Future<Adapter<T>> initialize(
      {bool? remote,
      required Map<String, Adapter> adapters,
      required Ref ref}) async {
    if (isInitialized) return this as Adapter<T>;

    // initialize attributes
    _adapters = adapters;
    _remote = remote ?? true;
    _ref = ref;

    storage.db.execute('''
      CREATE TABLE IF NOT EXISTS $internalType (
        key INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT
      );
    ''');

    // hook for clients
    await onInitialized();

    return this as Adapter<T>;
  }

  @override
  void dispose() {}

  // local methods

  /// Returns all models of type [T] in local storage.
  List<T> findAllLocal() {
    throw UnimplementedError('');
  }

  /// Finds many models of type [T] by [keys] in local storage.
  List<T> findManyLocal(Iterable<String> keys) {
    throw UnimplementedError('');
  }

  /// Finds model of type [T] by [key] in local storage.
  T? findOneLocal(String? key) {
    final intKey = key?.detypifyKey();
    if (intKey == null) return null;
    final result = storage.db
        .select('SELECT key, data FROM $internalType WHERE key = ?', [intKey]);
    final data = result.firstOrNull?['data'];
    if (data != null) {
      final map = Map<String, dynamic>.from(jsonDecode(data));
      final ds = deserialize(map,
          key: result.firstOrNull?['key'].toString().typifyWith(internalType));
      return ds;
    }
    return null;
  }

  T? findOneLocalById(Object id) {
    final key = core.getKeyForId(internalType, id);
    return findOneLocal(key);
  }

  /// Whether [key] exists in local storage.
  bool exists(String key) {
    throw UnimplementedError('');
  }

  /// Saves model of type [T] in local storage.
  ///
  /// By default notifies this modification to the associated [CoreNotifier].
  T saveLocal(T model, {bool notify = true}) {
    if (model._key == null) {
      throw Exception("Model must be initialized:\n\n$model");
    }
    final intKey = model._key!.detypifyKey();

    final map = serialize(model, withRelationships: false);
    final data = jsonEncode(map);
    storage.db.execute(
        'REPLACE INTO $internalType (key, data) VALUES (?, ?)', [intKey, data]);
    return model;
  }

  Future<void> saveManyLocal(Iterable<DataModelMixin> models,
      {bool notify = true}) async {
    throw UnimplementedError('');
  }

  /// Deletes model of type [T] from local storage.
  void deleteLocal(T model, {bool notify = true}) {
    throw UnimplementedError('');
  }

  /// Deletes model with [id] from local storage.
  void deleteLocalById(Object id, {bool notify = true}) {
    throw UnimplementedError('');
  }

  /// Deletes models with [keys] from local storage.
  void deleteLocalByKeys(Iterable<String> keys, {bool notify = true}) {
    throw UnimplementedError('');
  }

  /// Deletes all models of type [T] in local storage.
  ///
  /// If you need to clear all models, use the
  /// `adapterProviders` map exposed on your `main.data.dart`.
  Future<void> clearLocal() {
    // leave async in case some impls need to remove files
    throw UnimplementedError('');
  }

  /// Counts all models of type [T] in local storage.
  int get countLocal {
    throw UnimplementedError('');
  }

  /// Gets all keys of type [T] in local storage.
  List<String> get keys {
    throw UnimplementedError('');
  }

  // serialize interfaces

  @protected
  @visibleForTesting
  Future<Map<String, dynamic>> serializeAsync(T model,
      {bool withRelationships = true});

  @protected
  @visibleForTesting
  Future<DeserializedData<T>> deserializeAsync(Object? data, {String? key});

  /// Implements global request error handling.
  ///
  /// Defaults to throw [e] unless it is an HTTP 404
  /// or an `OfflineException`.
  ///
  /// NOTE: `onError` arguments throughout the API are used
  /// to override this default behavior.
  FutureOr<R?> onError<R>(
    DataException e,
    DataRequestLabel? label,
  ) {
    if (e.statusCode == 404 || e is OfflineException) {
      return null;
    }
    throw e;
  }

  void log(DataRequestLabel label, String message, {int logLevel = 1}) {
    if (this.logLevel >= logLevel) {
      final now = DateTime.now();
      final timestamp =
          '${now.second.toString().padLeft(2, '0')}:${now.millisecond.toString().padLeft(3, '0')}';
      print('$timestamp ${' ' * label.indentation * 2}[$label] $message');
    }
  }

  /// After model initialization hook
  @protected
  void onModelInitialized(T model) {}

  // offline

  /// Determines whether [error] was an offline error.
  @protected
  @visibleForTesting
  bool isOfflineError(Object? error) {
    final commonExceptions = [
      // timeouts via http's `connectionTimeout` are also socket exceptions
      'SocketException',
      'HttpException',
      'HandshakeException',
      'TimeoutException',
    ];

    // we check exceptions with strings to avoid importing `dart:io`
    final err = error.runtimeType.toString();
    return commonExceptions.any(err.contains);
  }

  @protected
  @visibleForTesting
  @nonVirtual
  Set<OfflineOperation<T>> get offlineOperations {
    // TODO restore
    final edges = []; // storage.edgesFor([(_offlineAdapterKey, null)]);
    return edges
        .map((e) {
          try {
            // extract type from e.g. _offline:findOne/users#3@d7bcc9
            final label = DataRequestLabel.parse(e.name.denamespace());
            if (label.type == internalType) {
              // get first edge value
              final map = json.decode(e.to) as Map<String, dynamic>;
              return OfflineOperation<T>.fromJson(
                  label, map, this as Adapter<T>);
            }
          } catch (_) {
            // TODO restore
            // if there were any errors parsing labels or json ignore and remove
            // storage.removeEdgesFor([(_offlineAdapterKey, e.name)]);
          }
        })
        .nonNulls
        .toSet();
  }

  Object? _resolveId(Object obj) {
    return obj is T ? obj.id : obj;
  }

  bool get _isTesting {
    return ref.read(httpClientProvider) != null;
  }

  //

  @protected
  @nonVirtual
  T internalWrapStopInit(Function fn, {String? key}) {
    _stopInitialization = true;
    late T model;
    try {
      model = fn();
    } finally {
      _stopInitialization = false;
    }
    return initModel(model, key: key);
  }

  @protected
  @nonVirtual
  T initModel(T model, {String? key, Function(T)? onModelInitialized}) {
    if (_stopInitialization) {
      return model;
    }

    // // (before -> after remote save)
    // // (1) if noid -> noid => `key` is the key we want to keep
    // // (2) if id -> noid => use autogenerated key (`key` should be the previous (derived))
    // // so we can migrate rels
    // // (3) if noid -> id => use derived key (`key` should be the previous (autogen'd))
    // // so we can migrate rels

    if (model._key == null) {
      model._key = key ?? core.getKeyForId(internalType, model.id);
      if (model._key != key) {
        _initializeRelationships(model, fromKey: key);
      } else {
        _initializeRelationships(model);
      }

      onModelInitialized?.call(model);
    }
    return model;
  }

  void _initializeRelationships(T model, {String? fromKey}) {
    final metadatas = relationshipMetas.values;
    for (final metadata in metadatas) {
      final relationship = metadata.instance(model);
      if (relationship != null) {
        // if rel was omitted, fill with info of previous key
        // TODO optimize: put outside loop and query edgesFor just once
        if (fromKey != null && relationship._uninitializedKeys == null) {
          // TODO restore
          // final edges = storage.edgesFor({(fromKey, metadata.name)});
          // relationship._uninitializedKeys = edges.map((e) => e.to).toSet();
        }
        relationship.initialize(
          ownerKey: model._key!,
          name: metadata.name,
          inverseName: metadata.inverseName,
        );
      }
    }
  }

  Map<String, dynamic> serialize(T model, {bool withRelationships = true}) {
    throw UnimplementedError('');
  }

  T deserialize(Map<String, dynamic> map, {String? key}) {
    throw UnimplementedError('');
  }

  Map<String, RelationshipMeta> get relationshipMetas {
    throw UnimplementedError('');
  }

  Map<String, dynamic> transformSerialize(Map<String, dynamic> map,
      {bool withRelationships = true}) {
    for (final e in relationshipMetas.entries) {
      final key = e.key;
      if (withRelationships) {
        final ignored = e.value.serialize == false;
        if (ignored) map.remove(key);

        if (map[key] is HasMany) {
          map[key] = (map[key] as HasMany).keys;
        } else if (map[key] is BelongsTo) {
          map[key] = map[key].key;
        }

        if (map[key] == null) map.remove(key);
      } else {
        map.remove(key);
      }
    }
    return map;
  }

  Map<String, dynamic> transformDeserialize(Map<String, dynamic> map) {
    // ensure value is dynamic (argument might come in as Map<String, String>)
    map = Map<String, dynamic>.from(map);
    for (final e in relationshipMetas.entries) {
      final key = e.key;
      final keyset = map[key] is Iterable
          ? {...(map[key] as Iterable)}
          : {if (map[key] != null) map[key].toString()};
      final ignored = e.value.serialize == false;
      map[key] = {
        '_': (map.containsKey(key) && !ignored) ? keyset : null,
      };
    }
    return map;
  }
}

/// Annotation on a [DataModelMixin] model to request an [Adapter] be generated for it.
///
/// Takes a list of [adapters] to be mixed into this [Adapter].
/// Public methods of these [adapters] mixins will be made available in the adapter
/// via extensions.
///
/// A classic example is:
///
/// ```
/// @JsonSerializable()
/// @DataAdapter([JSONAPIAdapter])
/// class Todo with DataModel<Todo> {
///   @override
///   final int id;
///   final String title;
///   final bool completed;
///
///   Todo({this.id, this.title, this.completed = false});
/// }
///```
class DataAdapter {
  final List<Type> adapters;
  final bool remote;
  const DataAdapter(this.adapters, {this.remote = true});
}
