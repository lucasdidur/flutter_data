import 'package:flutter_data/flutter_data.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../_support/family.dart';
import '../../_support/house.dart';
import '../../_support/mocks.dart';
import '../../_support/person.dart';
import '../../_support/setup.dart';

void main() async {
  setUp(setUpFn);
  tearDown(tearDownFn);

  test('set owner in relationships', () {
    final person = Person(id: '1', name: 'John', age: 37).init(owner);
    final house = House(id: '31', address: '123 Main St').init(owner);
    final house2 = House(id: '2', address: '456 Main St').init(owner);

    final family = Family(
        id: '1',
        surname: 'Smith',
        residence: BelongsTo<House>(house),
        persons: HasMany<Person>({person}));

    // no dataId associated to family or relationships
    expect(family.residence.key, isNull);
    expect(family.persons.keys, isEmpty);

    family.init(owner);

    // relationships are now associated to a key
    expect(family.residence.key, graph.getKeyForId('houses', '31'));
    expect(family.persons.keys.first, graph.getKeyForId('people', '1'));

    // ensure there are not more than 1 key
    family.residence.value = house2;
    expect(family.residence.keys, hasLength(1));
  });

  test('assignment with both uninitialized', () {
    final family =
        Family(id: '1', surname: 'Smith', residence: BelongsTo<House>());
    final house = House(id: '1', address: '456 Lemon Rd');

    // since both are not initialized, house will be added to the queue
    family.residence.value = house;
    expect(family.residence.value, isNull);

    // initialize, flush the queue and verify
    family.init(owner);
    expect(family.residence.value, house);
  });

  test('assignment only with owner initialized', () {
    final family =
        Family(id: '1', surname: 'Smith', residence: BelongsTo<House>())
            .init(owner);
    final house = House(id: '1', address: '456 Lemon Rd');

    family.residence.value = house;
    expect(family.residence.value, house);
  });

  test('assignment only with value initialized', () {
    final family =
        Family(id: '1', surname: 'Smith', residence: BelongsTo<House>());
    final house = House(id: '1', address: '456 Lemon Rd').init(owner);

    family.residence.value = house;
    expect(family.residence.value, isNull);
    family.init(owner);
    expect(family.residence.value, house);
  });

  test('watch', () async {
    final family = Family(
      id: '22',
      surname: 'Besson',
      residence: BelongsTo<House>(),
    ).init(owner);

    final notifier = family.residence.watch();
    final listener = Listener<House>();
    dispose = notifier.addListener(listener, fireImmediately: false);

    family.residence.value = House(id: '2', address: '456 Main St').init(owner);
    await oneMs();

    verify(listener(argThat(
      isA<House>().having((h) => h.address, 'address', startsWith('456')),
    ))).called(1);

    family.residence.value = House(id: '1', address: '123 Main St').init(owner);
    await oneMs();

    verify(listener(argThat(
      isA<House>().having((h) => h.address, 'address', startsWith('123')),
    ))).called(1);

    family.residence.value = null;
    await oneMs();

    verify(listener(argThat(isNull))).called(1);
  });
}
