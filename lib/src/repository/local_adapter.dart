part of flutter_data;

/// An adapter interface to access local storage.
///
/// Identity in this layer is enforced by keys.
class LocalAdapter<T extends DataModelMixin<T>> with _Lifecycle {
  @protected
  LocalAdapter(Ref ref)
      : core = ref.read(_coreNotifierProvider),
        storage = ref.read(localStorageProvider);

  @mustCallSuper
  @nonVirtual
  Future<LocalAdapter<T>> initialize() async {
    storage.db.execute('''
      CREATE TABLE IF NOT EXISTS $internalType (
        key INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT
      );
    ''');

    return this;
  }

  @protected
  @visibleForTesting
  final CoreNotifier core;

  @protected
  @visibleForTesting
  final LocalStorage storage;

  String get internalType => DataHelpers.getInternalType<T>();

  bool _stopInitialization = false;

  /// Returns all models of type [T] in local storage.
  List<T> findAll() {
    throw UnimplementedError('');
  }

  /// Finds model of type [T] by [key] in local storage.
  T? findOne(String? key) {
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

  /// Finds many models of type [T] by [keys] in local storage.
  List<T> findMany(Iterable<String> keys) {
    throw UnimplementedError('');
  }

  /// Whether [key] exists in local storage.
  bool exists(String key) {
    throw UnimplementedError('');
  }

  /// Saves model of type [T] with [key] in local storage.
  ///
  /// By default notifies this modification to the associated [CoreNotifier].
  @protected
  @visibleForTesting
  T save(String key, T model, {bool notify = true}) {
    final intKey = key.detypifyKey();

    final map = serialize(model, withRelationships: false);
    final data = jsonEncode(map);
    storage.db.execute(
        'REPLACE INTO $internalType (key, data) VALUES (?, ?)', [intKey, data]);
    return model;
  }

  /// Deletes model of type [T] with [key] from local storage.
  ///
  /// By default notifies this modification to the associated [CoreNotifier].
  @protected
  @visibleForTesting
  void delete(String key, {bool notify = true}) {
    throw UnimplementedError('');
  }

  void deleteKeys(Iterable<String> keys, {bool notify = true}) {
    throw UnimplementedError('');
  }

  /// Deletes all models of type [T] in local storage.
  @protected
  @visibleForTesting
  Future<void> clear() {
    throw UnimplementedError('');
  }

  /// Counts all models of type [T] in local storage.
  int get count {
    throw UnimplementedError('');
  }

  /// Gets all keys of type [T] in local storage.
  List<String> get keys {
    throw UnimplementedError('');
  }

  Future<void> saveMany(Iterable<DataModelMixin> models, {bool notify = true}) {
    throw UnimplementedError('');
  }

  // model initialization

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

  @override
  void dispose() {
    // TODO: implement dispose
  }

  @override
  // TODO: implement isInitialized
  bool get isInitialized => throw UnimplementedError();
}
