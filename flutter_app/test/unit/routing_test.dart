import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/domain/models/enums.dart';
import 'package:powerline/domain/models/models2.dart';
import 'package:powerline/engines/routing/routing.dart';

DeviceRecord dev(String id, {bool ring = true, bool revoked = false, bool thisDev = false}) =>
    DeviceRecord(id: id, name: id, type: DeviceType.androidPhone, lastActive: DateTime(2026), ringEnabled: ring, revoked: revoked, isThisDevice: thisDev);

void main() {
  final openHours = BusinessHours(weekly: {
    for (var d = 1; d <= 7; d++) d: [[0, 24]]
  });
  final closedHours = const BusinessHours(weekly: {});

  test('ring all rings every active device', () {
    final d = routeInboundCall(
      rules: const [RoutingRule(id: 'r', name: 'all', strategy: RoutingStrategy.ringAll)],
      devices: [dev('a'), dev('b'), dev('c', revoked: true)],
      hours: openHours,
      localNow: DateTime(2026, 1, 1, 10),
    );
    expect(d.action, 'ring');
    expect(d.ringDeviceIds, containsAll(['a', 'b']));
    expect(d.ringDeviceIds, isNot(contains('c')));
  });

  test('business-hours rule sends after-hours to AI', () {
    final d = routeInboundCall(
      rules: const [
        RoutingRule(id: 'r', name: 'bh', strategy: RoutingStrategy.ringAll, businessHoursOnly: true, afterHoursAction: 'ai-agent')
      ],
      devices: [dev('a')],
      hours: closedHours,
      localNow: DateTime(2026, 1, 1, 3),
    );
    expect(d.action, 'ai-agent');
  });

  test('ring selected only rings chosen devices', () {
    final d = routeInboundCall(
      rules: const [
        RoutingRule(id: 'r', name: 'sel', strategy: RoutingStrategy.ringSelected, deviceIds: ['b'])
      ],
      devices: [dev('a'), dev('b')],
      hours: openHours,
      localNow: DateTime(2026, 1, 1, 10),
    );
    expect(d.ringDeviceIds, ['b']);
  });

  test('AI overflow when nobody available', () {
    final d = routeInboundCall(
      rules: const [RoutingRule(id: 'r', name: 'of', strategy: RoutingStrategy.aiOverflow)],
      devices: [dev('a', ring: false)],
      hours: openHours,
      localNow: DateTime(2026, 1, 1, 10),
    );
    expect(d.action, 'ai-agent');
  });

  test('forward when offline forwards only when no active devices', () {
    final d = routeInboundCall(
      rules: const [
        RoutingRule(id: 'r', name: 'fw', strategy: RoutingStrategy.forwardWhenOffline, forwardTo: '+15551230000')
      ],
      devices: [dev('a', ring: false)],
      hours: openHours,
      localNow: DateTime(2026, 1, 1, 10),
    );
    expect(d.action, 'forward');
    expect(d.forwardTo, '+15551230000');
  });

  test('no rule matches -> voicemail fallback', () {
    final d = routeInboundCall(
      rules: const [],
      devices: [dev('a')],
      hours: openHours,
      localNow: DateTime(2026, 1, 1, 10),
    );
    expect(d.action, 'voicemail');
  });

  test('business hours isOpenAt respects windows and holidays', () {
    final bh = BusinessHours(weekly: const {4: [[9, 17]]}, holidays: const ['2026-01-01']);
    expect(bh.isOpenAt(DateTime(2026, 1, 8, 10)), isTrue); // Thursday 10am
    expect(bh.isOpenAt(DateTime(2026, 1, 8, 20)), isFalse); // Thursday 8pm
    expect(bh.isOpenAt(DateTime(2026, 1, 1, 10)), isFalse); // holiday
  });
}
