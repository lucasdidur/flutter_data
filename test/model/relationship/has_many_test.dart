import 'package:flutter_data/flutter_data.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../_support/book.dart';
import '../../_support/familia.dart';
import '../../_support/house.dart';
import '../../_support/person.dart';
import '../../_support/setup.dart';
import '../../mocks.dart';

void main() async {
  setUp(setUpFn);
  tearDown(tearDownFn);

  test('HasMany ids', () {
    final f1 = Familia(surname: 'Sanchez');
    f1.persons.add(Person(id: '1', name: 'Manuel'));
    f1.persons.add(Person(id: '2', name: 'Carlos'));
    // id is between brackets as familia is not initialized
    expect(f1.persons.toString(), 'HasMany<Person>([1], [2])');

    f1.init(container.read);

    expect(f1.persons.ids, f1.persons.map((e) => e.id));
    expect(f1.persons.toString(), 'HasMany<Person>(1, 2)');
  });

  test('behaves like a collection (without init/models)', () {
    final anne = Person(name: 'Anne', age: 59);
    final f1 = Familia(surname: 'Mayer', persons: {anne}.asHasMany);

    f1.persons.add(anne);
    f1.persons.add(anne);
    expect(f1.persons.length, 1);

    final agnes = Person(name: 'Agnes', age: 29);
    f1.persons.add(agnes);
    expect(f1.persons.length, 2);

    f1.persons.remove(anne);
    expect(f1.persons.toSet(), {agnes});
  });

  test('behaves like a collection (with init)', () {
    final pete = Person(name: 'Pete', age: 29);
    final anne = Person(name: 'Anne', age: 59);
    final residence = House(address: '1322 Hill Rd');
    final f2 = Familia(
      surname: 'Sumberg',
      persons: {pete}.asHasMany,
      cottage: BelongsTo(),
      residence: residence.asBelongsTo,
    ).init(container.read);

    f2.persons.add(pete);
    f2.persons.add(pete);
    expect(f2.persons.length, 1);

    f2.persons.add(anne);
    expect(f2.persons.length, 2);

    f2.persons.remove(anne);
    expect(f2.persons.toSet(), {pete});

    expect(f2.relationships(),
        unorderedEquals([f2.persons, f2.residence, f2.cottage]));
    expect(f2.relationships().whereType<HasMany>(), [f2.persons]);
    expect(f2.relationships(withValue: true),
        unorderedEquals([f2.residence, f2.persons]));
  });

  test('assignment with relationship initialized & uninitialized', () {
    final familia = Familia(id: '1', surname: 'Smith', persons: HasMany());
    final person = Person(id: '1', name: 'Flavio', age: 12);

    familia.persons.add(person);
    expect(familia.persons.contains(person), isTrue);

    familia.init(container.read);

    familia.persons.add(person);
    expect(familia.persons.contains(person), isTrue);
  });

  test('use fromJson constructor without initialization', () {
    // internal format
    final persons = HasMany<Person>.fromJson({
      '_': [
        ['k1', 'k2'],
        false,
      ]
    });
    expect(persons.keys, {'k1', 'k2'});
    expect(persons, isEmpty);
  });

  test('watch', () async {
    final familia = Familia(
      id: '1',
      surname: 'Smith',
      persons: HasMany<Person>(),
    ).init(container.read);

    final notifier = familia.persons.watch();
    final listener = Listener<Set<Person>>();
    dispose = notifier.addListener(listener, fireImmediately: false);

    final p1 = Person(name: 'a', age: 1);
    final p2 = Person(name: 'b', age: 2);

    familia.persons.add(p1);
    await oneMs();

    verify(listener({p1})).called(1);

    familia.persons.add(p2);
    await oneMs();

    verify(listener({p1, p2})).called(1);

    familia.persons.add(p2);
    await oneMs();

    // doesn't show up as p2 was already present!
    verifyNever(listener({p1, p2}));

    familia.persons.remove(p1);
    await oneMs();

    verify(listener({p2})).called(1);

    familia.persons.add(p1);
    await oneMs();

    verify(listener({p1, p2})).called(1);
  });

  test('remove relationship', () async {
    final b1 = Book(id: 1).init(container.read);
    await b1.save();

    final a1 = BookAuthor(id: 1, name: 'Walter', books: {b1}.asHasMany)
        .init(container.read);
    await a1.save();

    final a2 = a1.copyWith(books: HasMany.remove()).was(a1);
    await a2.save();
    expect(a2.books!.toSet(), <Book>{});
    expect(a1.books!.toSet(), <Book>{});
  });
}
