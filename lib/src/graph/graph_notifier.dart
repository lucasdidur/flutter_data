part of flutter_data;

/// A bidirected graph data structure that notifies
/// modification events through a [StateNotifier].
///
/// It's a core framework component as it holds all
/// relationship information.
///
/// Watchers like [Repository.watchAllNotifier] or [BelongsTo.watch]
/// make use of it.
///
/// Its public API requires all keys and metadata to be namespaced
/// i.e. `manager:key`
class GraphNotifier extends DelayedStateNotifier<DataGraphEvent>
    with _Lifecycle {
  final Ref ref;
  @protected
  GraphNotifier(this.ref);

  ObjectboxLocalStorage get _localStorage => ref.read(localStorageProvider);

  bool _doAssert = true;

  @override
  bool isInitialized = false;

  // key: (typeId?), we use a record to indicate removal with (null,)
  final Map<String, (String?,)> _mappingBuffer = {};
  final Set<Edge> _unsavedEdges = {};
  final Set<Edge> _unsavedRemovedEdges = {};

  late Store _store;
  late Box<StoredModel> _storedModelBox;
  late Box<Edge> _edgeBox;

  /// Initializes storage systems
  Future<GraphNotifier> initialize() async {
    if (isInitialized) return this;
    await _localStorage.initialize();

    try {
      _store = openStore(
        directory: path_helper.join(_localStorage.path, 'flutter_data'),
        queriesCaseSensitiveDefault: false,
      );
      _storedModelBox = _store.box<StoredModel>();
      _edgeBox = _store.box<Edge>();
    } catch (e, stackTrace) {
      print('[flutter_data] Objectbox failed to open:\n$e\n$stackTrace');
    }

    if (_localStorage.clear == LocalStorageClearStrategy.always) {
      // TODO no way of removing everything?
      _storedModelBox.removeAll();
      _edgeBox.removeAll();
    }

    isInitialized = true;
    return this;
  }

  @override
  void dispose() {
    if (isInitialized) {
      _store.close();
      isInitialized = false;
      super.dispose();
    }
  }

  void clear() {
    _edgeBox.removeAll();
  }

  // Key-related methods

  /// Finds a model's key.
  ///
  ///  - Attempts a lookup by [type]/[id]
  ///  - If the key was not found, it returns a default [keyIfAbsent]
  ///    (if provided)
  ///  - It associates [keyIfAbsent] with the supplied [type]/[id]
  ///    (if both [keyIfAbsent] & [type]/[id] were provided)
  String? getKeyForId(String type, Object? id, {String? keyIfAbsent}) {
    type = DataHelpers.internalTypeFor(type);

    if (id != null) {
      var entry = _mappingBuffer.entries
          .firstWhereOrNull((e) => e.value.$1 == id.typifyWith(type));
      if (entry?.value != null) {
        if (entry!.value.$1 == null) {
          return null;
        }
        return entry.key;
      }

      // if it wasn't found fall back to DB (for reads)
      final keys = _storedModelBox
          .query(StoredModel_.typeId.equals(id.typifyWith(type)))
          .build()
          .property(StoredModel_.key)
          .find();
      if (keys.isNotEmpty) {
        return keys.first.typifyWith(type);
      }
      if (keyIfAbsent != null) {
        // Buffer write
        final typeId = id.typifyWith(type);
        _mappingBuffer[keyIfAbsent] = (typeId,);
        return keyIfAbsent;
      }
    } else if (keyIfAbsent != null) {
      return keyIfAbsent;
    }
    return null;
  }

  /// Finds an ID, given a [key].
  Object? getIdForKey(String key) {
    final mapping = _mappingBuffer[key];
    if (mapping != null) {
      if (mapping.$1 == null) {
        return null;
      }
      return mapping.$1!.detypify();
    }

    final typeIds = _storedModelBox
        .query(StoredModel_.key.equals(key.detypify() as int))
        .build()
        .property(StoredModel_.typeId)
        .find();

    if (typeIds.isNotEmpty) {
      return typeIds.first.detypify();
    }
    return null;
  }

  /// Removes type-ID mapping for [key]
  void removeIdForKey(String key,
      {String? type, Object? id, bool notify = true}) {
    final mapping = _mappingBuffer[key];
    final typeId = mapping?.$1 ?? (id != null ? id.typifyWith(type!) : null);
    _mappingBuffer[key] = (null,);
    state = DataGraphEvent(
        keys: [if (typeId != null) typeId],
        type: DataGraphEventType.removeNode);
  }

  // nodes

  void _assertKey(String key) {
    if (_doAssert) {
      if (key.split(':').length != 2 || key.startsWith('_')) {
        throw AssertionError('''
Key "$key":
  - Key must be namespaced (my:key)
  - Key can't contain a colon (my:precious:key)
  - Namespace can't start with an underscore (_my:key)
''');
      }
    }
  }

  /// Obtains a node
  // Map<String, Set<String>> getNode(String key) {
  //   _assertKey(key);
  //   return _getNode(key);
  // }

  /// Returns whether [key] is present in this graph.
  ///
  /// [key] MUST be namespaced (e.g. `manager:key`)
  // bool hasNode(String key) {
  //   _assertKey(key);
  //   return _hasNode(key);
  // }

  /// Removes a node, [key] MUST be namespaced (e.g. `manager:key`)
  // void removeNode(String key, {bool notify = true}) {
  //   _assertKey(key);
  //   return _removeNode(key, notify: notify);
  // }

  // edges

  /// See [addEdge]
  // void addEdges(String from,
  //     {required String metadata,
  //     required Set<String> tos,
  //     String? inverseMetadata,
  //     bool notify = true}) {
  //   _assertKey(from);
  //   for (final to in tos) {
  //     _assertKey(to);
  //   }
  //   _assertKey(metadata);
  //   if (inverseMetadata != null) {
  //     _assertKey(inverseMetadata);
  //   }
  //   _addEdges(from,
  //       metadata: metadata, tos: tos, inverseMetadata: inverseMetadata);
  // }

  /// Returns edge by [metadata]
  ///
  /// [key] and [metadata] MUST be namespaced (e.g. `manager:key`)
  // Set<String> getEdge(String key, {required String metadata}) {
  //   _assertKey(key);
  //   _assertKey(metadata);
  //   return _getEdge(key, metadata: metadata);
  // }

  /// Adds a bidirectional edge:
  ///
  ///  - [from]->[to] with [metadata]
  ///  - [to]->[from] with [inverseMetadata]
  ///
  /// [from], [metadata] & [inverseMetadata] MUST be namespaced (e.g. `manager:key`)
  // void addEdge(String from, String to,
  //     {required String metadata, String? inverseMetadata, bool notify = true}) {
  //   _assertKey(from);
  //   _assertKey(to);
  //   _assertKey(metadata);
  //   if (inverseMetadata != null) {
  //     _assertKey(inverseMetadata);
  //   }
  //   return _addEdge(from, to,
  //       metadata: metadata, inverseMetadata: inverseMetadata, notify: notify);
  // }

  /// See [removeEdge]
  // void removeEdges(String from,
  //     {required String metadata,
  //     Iterable<String> tos = const [],
  //     String? inverseMetadata,
  //     bool notify = true}) {
  //   _assertKey(from);
  //   for (final to in tos) {
  //     _assertKey(to);
  //   }
  //   _assertKey(metadata);
  //   if (inverseMetadata != null) {
  //     _assertKey(inverseMetadata);
  //   }
  //   return _removeEdges(from, metadata: metadata, notify: notify);
  // }

  /// Removes a bidirectional edge:
  ///
  ///  - [from]->[to] with [metadata]
  ///  - [to]->[from] with [inverseMetadata]
  ///
  /// [from], [metadata] & [inverseMetadata] MUST be namespaced (e.g. `manager:key`)
  // void removeEdge(String from, String to,
  //     {required String metadata, String? inverseMetadata, bool notify = true}) {
  //   _assertKey(from);
  //   _assertKey(to);
  //   _assertKey(metadata);
  //   if (inverseMetadata != null) {
  //     _assertKey(inverseMetadata);
  //   }
  //   return _removeEdge(from, to, metadata: metadata, notify: notify);
  // }

  /// Returns whether the requested edge is present in this graph.
  ///
  /// [key] and [metadata] MUST be namespaced (e.g. `manager:key`)
  // bool hasEdge(String key, {required String metadata}) {
  //   _assertKey(key);
  //   _assertKey(metadata);
  //   return _hasEdge(key, metadata: metadata);
  // }

  // utils

  /// Returns a [Map] representation of this graph from the underlying storage.
  Map<String, Map<String, List<String>>> toMap() => _toMap();

  /// Returns a [Map] representation of the internal ID db
  Map<String, String> toIdMap() {
    final models = _storedModelBox.getAll();
    return {
      for (final e in _mappingBuffer.entries)
        if (e.value.$1 != null) e.key: e.value.$1!,
      for (final m in models) m.key.typifyWith(m.type): m.typeId
    };
  }

  void debugMap() => _prettyPrintJson(_toMap());

  void debugStore() => print(_storedModelBox.getAll().map((e) => e.toJson()));

  @protected
  @visibleForTesting
  void debugAssert(bool value) => _doAssert = value;

  // private API

  // reads

  // Map<String, Set<String>> _getNode(String key) {
  //   final edges = _edgeBox
  //       .query(Edge_.from.equals(key) | Edge_.to.equals(key))
  //       .build()
  //       .find();
  //   final grouped = edges.groupListsBy((e) => e.name);
  //   return {
  //     for (final e in grouped.entries)
  //       e.key: e.value.map((e) => e.from == key ? e.to : e.from).toSet()
  //   };
  // }

  // bool _hasNode(String key) {
  //   return _store
  //           .box<Edge>()
  //           .query(Edge_.from.equals(key) | Edge_.to.equals(key))
  //           .build()
  //           .count() >
  //       0;
  // }

  // Set<String> _getEdge(String key, {required String metadata}) {
  //   final edges = _store
  //       .box<Edge>()
  //       .query((Edge_.from.equals(key).and(Edge_.name.equals(metadata)))
  //           .or(Edge_.to.equals(key).and(Edge_.inverseName.equals(metadata))))
  //       .build()
  //       .find();
  //   return {for (final e in edges) e.from == key ? e.to : e.from};
  // }

  // bool _hasEdge(String key, {required String metadata}) {
  //   return _store
  //           .box<Edge>()
  //           .query((Edge_.from.equals(key).and(Edge_.name.equals(metadata))).or(
  //               Edge_.to.equals(key).and(Edge_.inverseName.equals(metadata))))
  //           .build()
  //           .count() >
  //       0;
  // }

  // writes

  // void _removeNode(String key, {bool notify = true}) {
  //   _edgeBox
  //       .query(Edge_.from.equals(key) | Edge_.to.equals(key))
  //       .build()
  //       .remove();
  //   if (notify) {
  //     state = DataGraphEvent(keys: [key], type: DataGraphEventType.removeNode);
  //   }
  // }

  // void _addEdge(String from, String to,
  //     {required String metadata, String? inverseMetadata, bool notify = true}) {
  //   _addEdges(from,
  //       tos: {to},
  //       metadata: metadata,
  //       inverseMetadata: inverseMetadata,
  //       notify: notify);
  // }

  // void _addEdges(String from,
  //     {required String metadata,
  //     required Set<String> tos,
  //     String? inverseMetadata,
  //     bool clearExisting = false,
  //     bool notify = true}) {
  //   if (tos.isEmpty) {
  //     // empty tos means all
  //     if (clearExisting) {
  //       _getRemoveEdgesQuery(_edgeBox, from, metadata: metadata).remove();
  //     }
  //     return;
  //   }

  //   final edges = tos.map(
  //     (to) => Edge(
  //         id: 0, // autoincrement
  //         from: from,
  //         name: metadata,
  //         to: to,
  //         inverseName: inverseMetadata),
  //   );

  //   if (clearExisting) {
  //     _getRemoveEdgesQuery(_edgeBox, from, tos: tos, metadata: metadata)
  //         .remove();
  //   }

  //   for (final edge in edges) {
  //     _edgeBuffer.add((edge, removed: false));
  //   }

  //   if (notify) {
  //     if (clearExisting) {
  //       state = DataGraphEvent(
  //         keys: [from, ...tos],
  //         metadata: metadata,
  //         type: DataGraphEventType.removeEdge,
  //       );
  //     }
  //     state = DataGraphEvent(
  //       keys: [from, ...tos],
  //       metadata: metadata,
  //       type: DataGraphEventType.addEdge,
  //     );
  //   }
  // }

  // void _removeEdge(String from, String to,
  //     {required String metadata, bool notify = true}) {
  //   _removeEdges(from, tos: {to}, metadata: metadata, notify: notify);
  // }

  // Query<Edge> _getRemoveEdgesQuery(Box<Edge> box, String from,
  //     {required String metadata, Set<String>? tos}) {
  //   var q1 = Edge_.from.equals(from) & Edge_.name.equals(metadata);
  //   if (tos != null) {
  //     q1 = q1.andAll(tos.map((to) => Edge_.to.equals(to)).toList());
  //   }
  //   var q2 = Edge_.to.equals(from) & Edge_.inverseName.equals(metadata);
  //   if (tos != null) {
  //     q2 = q2.andAll(tos.map((to) => Edge_.from.equals(to)).toList());
  //   }
  //   return box.query(q1 | q2).build();
  // }

  // void _removeEdges(String from,
  //     {required String metadata, Set<String>? tos, bool notify = true}) {
  //   _getRemoveEdgesQuery(_edgeBox, from, metadata: metadata, tos: tos).remove();

  //   if (notify) {
  //     state = DataGraphEvent(
  //       keys: [from, ...?tos],
  //       metadata: metadata,
  //       type: DataGraphEventType.removeEdge,
  //     );
  //   }
  // }

  void _notify(List<String> keys,
      {String? metadata, required DataGraphEventType type}) {
    if (mounted) {
      state = DataGraphEvent(type: type, metadata: metadata, keys: keys);
    }
  }

  // misc

  Map<String, Map<String, List<String>>> _toMap() {
    // final map = <String, Map<String, List<String>>>{};

    // final edges = _edgeBox.getAll();
    // for (final edge in edges) {
    //   map[edge.from] ??= {};
    //   map[edge.from]![edge.name] ??= [];
    //   map[edge.from]![edge.name]!.add(edge.to);
    // }
    // for (final edge in edges) {
    //   if (edge.inverseName != null) {
    //     map[edge.to] ??= {};
    //     map[edge.to]![edge.inverseName!] ??= [];
    //     map[edge.to]![edge.inverseName!]!.add(edge.from);
    //   }
    // }
    // return map;
    return {};
  }

  static JsonEncoder _encoder = JsonEncoder.withIndent('  ');
  static void _prettyPrintJson(Map<String, dynamic> map) {
    final prettyString = _encoder.convert(map);
    prettyString.split('\n').forEach((element) => print(element));
  }
}

enum DataGraphEventType {
  removeNode,
  updateNode,
  clear,
  addEdge,
  removeEdge,
  updateEdge,
  doneLoading,
}

extension DataGraphEventTypeX on DataGraphEventType {
  bool get isNode => [
        DataGraphEventType.updateNode,
        DataGraphEventType.removeNode,
      ].contains(this);
  bool get isEdge => [
        DataGraphEventType.addEdge,
        DataGraphEventType.updateEdge,
        DataGraphEventType.removeEdge,
      ].contains(this);
}

class DataGraphEvent {
  const DataGraphEvent({
    required this.keys,
    required this.type,
    this.metadata,
  });
  final List<String> keys;
  final DataGraphEventType type;
  final String? metadata;

  @override
  String toString() {
    return '${type.toShortString()}: $keys';
  }
}

extension _DataGraphEventX on DataGraphEventType {
  String toShortString() => toString().split('.').last;
}

final graphNotifierProvider =
    Provider<GraphNotifier>((ref) => GraphNotifier(ref));

extension PackerX on Packer {
  void packJson(Map<String, dynamic> map) {
    packMapLength(map.length);
    map.forEach((key, v) {
      packString(key);
      packDynamic(v);
    });
  }

  void packIterableDynamic(Iterable iterable) {
    packListLength(iterable.length);
    for (final v in iterable) {
      packDynamic(v);
    }
  }

  void packDynamic(dynamic value) {
    if (value is Map) {
      packInt(5);
      return packJson(Map<String, dynamic>.from(value));
    }

    final type = value.runtimeType;
    if (type == Null) {
      packInt(0);
      return packNull();
    }
    if (type == String) {
      packInt(1);
      return packString(value);
    }
    if (type == int) {
      // WORKAROUND: for some reason negative ints are not working
      // so we save it as a special string (prefixed with $__fd_n:)
      if ((value as int).isNegative) {
        packInt(1);
        return packString('\$__fd_n:$value');
      }
      packInt(2);
      return packInt(value);
    }
    if (type == double) {
      packInt(3);
      return packDouble(value);
    }
    if (type == bool) {
      packInt(4);
      return packBool(value);
    }
    // List of any type
    if (value is Iterable) {
      packInt(6);
      return packIterableDynamic(value.toList());
    }
    throw Exception('missing type $type ($value)');
  }
}

extension UnpackerX on Unpacker {
  Map<String, dynamic> unpackJson() {
    final map = <String, dynamic>{};
    final length = unpackMapLength();
    for (var i = 0; i < length; i++) {
      final key = unpackString();
      map[key!] = unpackDynamic();
    }
    return map;
  }

  List unpackListDynamic() {
    final list = [];
    final length = unpackListLength();
    for (var i = 0; i < length; i++) {
      list.add(unpackDynamic());
    }
    return list;
  }

  dynamic unpackDynamic() {
    final type = unpackInt();
    switch (type) {
      case 0:
        return unpackString();
      case 1:
        final str = unpackString();
        // WORKAROUND: we unpack a negative int (encoded with the $__fd_n: prefix)
        if (str != null && str.startsWith('\$__fd_n:-')) {
          return int.parse(str.split(':').last);
        }
        return str;
      case 2:
        return unpackInt();
      case 3:
        return unpackDouble();
      case 4:
        return unpackBool();
      case 5:
        return unpackJson();
      case 6:
        return unpackListDynamic();
      default:
        throw Exception('missing type $type');
    }
  }
}
