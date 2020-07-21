import 'package:flutter_data/flutter_data.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../_support/family.dart';
import '../../_support/mocks.dart';
import '../../_support/person.dart';
import '../../_support/setup.dart';

void main() async {
  setUp(setUpFn);
  tearDown(tearDownFn);

  test('HasMany is a Set', () {
    final anne = Person(name: 'Anne', age: 59).init(owner);
    final f1 = Family(surname: 'Mayer', persons: {anne}.asHasMany).init(owner);

    f1.persons.add(anne);
    f1.persons.add(anne);
    expect(f1.persons.length, 1);
    expect(f1.persons.lookup(anne), anne);

    final agnes = Person(name: 'Agnes', age: 29).init(owner);
    f1.persons.add(agnes);
    expect(f1.persons.length, 2);

    f1.persons.remove(anne);
    expect(f1.persons, {agnes});
    f1.persons.add(null);
    expect(f1.persons, {agnes});

    f1.persons.clear();
    expect(f1.persons.length, 0);
  });

  test('assignment with relationship initialized & uninitialized', () {
    final family = Family(id: '1', surname: 'Smith', persons: HasMany());
    final person = Person(id: '1', name: 'Flavio', age: 12);

    family.persons.add(person);
    expect(family.persons.contains(person), isTrue);

    family.init(owner);

    family.persons.add(person);
    expect(family.persons.contains(person), isTrue);
  });

  test('use relationship without initialization', () {
    final family = Family(id: '1', surname: 'Smith', persons: HasMany());
    final person = Person(id: '1', name: 'Flavio', age: 12);

    family.persons.add(person);
    expect(family.persons.contains(person), isTrue);
    expect(family.persons.lookup(person), person);
    expect(family.persons.toSet(), {person});

    family.persons.remove(person);
    expect(family.persons, isEmpty);
  });

  test('watch', () async {
    final family = Family(
      id: '1',
      surname: 'Smith',
      persons: HasMany<Person>(),
    ).init(owner);

    final p1 = Person(name: 'a', age: 1).init(owner);
    final p2 = Person(name: 'b', age: 2).init(owner);
    final notifier = family.persons.watch();

    final listener = Listener<Set<Person>>();
    dispose = notifier.addListener(listener, fireImmediately: false);

    family.persons.add(p1);
    await oneMs();

    verify(listener({p1})).called(1);

    family.persons.add(p2);
    await oneMs();

    verify(listener({p1, p2})).called(1);

    family.persons.add(p2);
    await oneMs();

    // doesn't show up as p2 was already present!
    verifyNever(listener({p1, p2}));

    family.persons.remove(p1);
    await oneMs();

    verify(listener({p2})).called(1);

    family.persons.add(p1);
    await oneMs();

    verify(listener({p1, p2})).called(1);
  });
}
