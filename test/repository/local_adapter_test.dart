import 'package:flutter_data/flutter_data.dart';
import 'package:test/test.dart';

import '../_support/familia.dart';
import '../_support/house.dart';
import '../_support/person.dart';
import '../_support/setup.dart';

void main() async {
  setUp(setUpFn);
  tearDown(tearDownFn);

  test('findOne with null key', () {
    final familia = container.familia.remoteAdapter.localAdapter.findOne(null);
    expect(familia, isNull);
  });

  test('save without ID', () async {
    final p1 = Person(name: 'Luis').saveLocal();
    final p2 = container.people.remoteAdapter.localAdapter.findOne(keyFor(p1))!;
    final p3 = p2.reloadLocal()!;

    expect(p1, p2);
    expect(p2, p3);
    expect(keyFor(p1), keyFor(p2));
    expect(keyFor(p2), keyFor(p3));
  });

  test('current and deserialized equals share same key', () async {
    final p = Person(id: '1', name: 'Luis');
    await container.people.save(p);
    final p2 = container.people.remoteAdapter.localAdapter
        .deserialize({'_id': '1', 'name': 'Luis'});
    expect(keyFor(p), keyFor(p2));
  });

  test('deserialize existing ID', () {
    final familiaLocalAdapter = container.familia.remoteAdapter.localAdapter;
    final familia = familiaLocalAdapter
        .deserialize({'id': '1098', 'surname': 'Moletto'}).saveLocal();

    expect(familiaLocalAdapter.keys, [keyFor(familia)]);
    expect(familia, Familia(id: '1098', surname: 'Moletto'));
  });

  test('deserialize many local for same remote ID', () {
    final familiaLocalAdapter = container.familia.remoteAdapter.localAdapter;
    final familia1 = familiaLocalAdapter.deserialize({
      'id': '1298',
      'surname': 'Helsinki',
    });

    final familia2 = familiaLocalAdapter.deserialize({
      'id': '1298',
      'surname': 'Oslo',
    });

    // since obj returned with same ID
    expect(keyFor(familia1), keyFor(familia2));
  });

  test('local serialize with and without relationships', () {
    final familiaLocalAdapter = container.familia.remoteAdapter.localAdapter;
    final person = Person(id: '4', name: 'Franco', age: 28);
    final house = House(id: '1', address: '123 Main St');

    final familia = Familia(
            id: '1',
            surname: 'Smith',
            residence: house.asBelongsTo,
            persons: {person}.asHasMany)
        .saveLocal();

    final map = familiaLocalAdapter.serialize(familia);
    expect(map, {
      'id': '1',
      'surname': 'Smith',
      'residence': keyFor(house),
      'persons': {keyFor(person)},
    });

    // now a familia without specified relationships,
    // still serializes the defaults
    final familia2 = Familia(id: '1', surname: 'Smith');

    final map2 = familiaLocalAdapter.serialize(familia2);
    expect(map2, {
      'id': '1',
      'surname': 'Smith',
      'residence': keyFor(house),
      'persons': {keyFor(person)},
    });

    final mapWithoutRelationships =
        familiaLocalAdapter.serialize(familia, withRelationships: false);
    expect(mapWithoutRelationships, {
      'id': '1',
      'surname': 'Smith',
    });
  });

  test('local deserialize', () {
    final familiaLocalAdapter = container.familia.remoteAdapter.localAdapter;
    final p1r = {Person(id: '1', name: 'Franco', age: 28)}.asHasMany;
    final h1r = House(id: '1', address: '12345 Long Rd').asBelongsTo;
    final fam = Familia(id: '1', surname: 'Smith', persons: p1r, cottage: h1r);

    final map = {
      'id': '1',
      'surname': 'Smith',
    };

    final familia = familiaLocalAdapter.deserialize(map);
    expect(
        familia,
        Familia(
          id: '1',
          surname: 'Smith',
          cottage: fam.cottage,
          persons: fam.persons,
        ));
  });

  test('local deserialize with relationships', () {
    final familiaLocalAdapter = container.familia.remoteAdapter.localAdapter;

    final obj = {
      'id': '1',
      'surname': 'Smith',
    };

    final familia = familiaLocalAdapter.deserialize(obj);
    House(id: '1', address: '123 Main St', owner: familia.asBelongsTo)
        .saveLocal();
    Person(id: '1', name: 'John', age: 21, familia: familia.asBelongsTo)
        .saveLocal();

    expect(familia, Familia(id: '1', surname: 'Smith'));
    expect(familia.residence.value!.address, '123 Main St');
    expect(familia.persons.first.age, 21);
  });

  test('local deserialize with custom local adapter', () {
    final nodeLocalAdapter = container.nodes.remoteAdapter.localAdapter;

    final obj = {
      'id': 1,
      'name': 'node',
    };

    final node = nodeLocalAdapter.deserialize(obj);
    expect(node.name, 'local');
  });

  test('relationships with serialized=false', () {
    final familia = Familia(id: '1', surname: 'Test').saveLocal();
    var house = container.houses.remoteAdapter.localAdapter.deserialize({
      'id': '99',
      'address': '456 Far Trail',
      'owner': keyFor(familia),
    }).saveLocal();
    final book = container.books.remoteAdapter.localAdapter.deserialize({
      'id': 1,
      'house': keyFor(house), // since it's a localAdapter deserialization
    }).saveLocal();
    expect(house.currentLibrary!.toList(), {book});

    final map = container.houses.remoteAdapter.localAdapter.serialize(house);
    // does not container currentLibrary which was serialize=false
    expect(map.containsKey('currentLibrary'), isFalse);
    // it does contain a regular relationship like owner
    expect(map.containsKey('owner'), isTrue);
  });
}
