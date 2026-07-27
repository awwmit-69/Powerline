/// Call routing rules + local routing simulator.
library;

import '../../domain/models/models2.dart';

enum RoutingStrategy {
  ringAll,
  ringSelected,
  sequential,
  simultaneous,
  forwardAfterDelay,
  forwardWhenBusy,
  forwardWhenOffline,
  directToVoicemail,
  aiFirst,
  humanFirst,
  aiOverflow,
}

class RoutingRule {
  final String id;
  final String name;
  final RoutingStrategy strategy;
  final List<String> deviceIds;
  final String? forwardTo;
  final int delaySeconds;
  final bool businessHoursOnly;
  final String afterHoursAction; // voicemail | ai-agent | forward
  final String? ringGroup;
  final int priority;

  const RoutingRule({
    required this.id,
    required this.name,
    required this.strategy,
    this.deviceIds = const [],
    this.forwardTo,
    this.delaySeconds = 20,
    this.businessHoursOnly = false,
    this.afterHoursAction = 'voicemail',
    this.ringGroup,
    this.priority = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'strategy': strategy.name, 'deviceIds': deviceIds,
        'forwardTo': forwardTo, 'delaySeconds': delaySeconds,
        'businessHoursOnly': businessHoursOnly, 'afterHoursAction': afterHoursAction,
        'ringGroup': ringGroup, 'priority': priority,
      };

  factory RoutingRule.fromJson(Map<String, dynamic> j) => RoutingRule(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        strategy: RoutingStrategy.values.firstWhere(
            (s) => s.name == j['strategy'], orElse: () => RoutingStrategy.ringAll),
        deviceIds: (j['deviceIds'] as List? ?? []).map((e) => e.toString()).toList(),
        forwardTo: j['forwardTo'] as String?,
        delaySeconds: (j['delaySeconds'] as num?)?.toInt() ?? 20,
        businessHoursOnly: j['businessHoursOnly'] as bool? ?? false,
        afterHoursAction: j['afterHoursAction'] as String? ?? 'voicemail',
        ringGroup: j['ringGroup'] as String?,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
      );
}

class RoutingDecision {
  final String action; // ring | forward | voicemail | ai-agent
  final List<String> ringDeviceIds;
  final String? forwardTo;
  final String explanation;
  const RoutingDecision({
    required this.action,
    this.ringDeviceIds = const [],
    this.forwardTo,
    required this.explanation,
  });
}

/// Pure function: given rules, devices, business hours and local time,
/// decide what an inbound call should do. Deterministic and unit-testable.
RoutingDecision routeInboundCall({
  required List<RoutingRule> rules,
  required List<DeviceRecord> devices,
  required BusinessHours hours,
  required DateTime localNow,
}) {
  final active = devices.where((d) => !d.revoked && d.ringEnabled).toList();
  final sorted = [...rules]..sort((a, b) => a.priority.compareTo(b.priority));

  for (final rule in sorted) {
    if (rule.businessHoursOnly && !hours.isOpenAt(localNow)) {
      switch (rule.afterHoursAction) {
        case 'ai-agent':
          return RoutingDecision(
              action: 'ai-agent',
              explanation: 'Rule "${rule.name}": outside business hours -> AI agent');
        case 'forward':
          return RoutingDecision(
              action: 'forward',
              forwardTo: rule.forwardTo,
              explanation: 'Rule "${rule.name}": outside business hours -> forward');
        default:
          return RoutingDecision(
              action: 'voicemail',
              explanation: 'Rule "${rule.name}": outside business hours -> voicemail');
      }
    }
    switch (rule.strategy) {
      case RoutingStrategy.directToVoicemail:
        return RoutingDecision(
            action: 'voicemail', explanation: 'Rule "${rule.name}": direct to voicemail');
      case RoutingStrategy.aiFirst:
        return RoutingDecision(
            action: 'ai-agent', explanation: 'Rule "${rule.name}": AI answers first');
      case RoutingStrategy.forwardAfterDelay:
      case RoutingStrategy.forwardWhenBusy:
      case RoutingStrategy.forwardWhenOffline:
        final offline = active.isEmpty;
        if (rule.strategy != RoutingStrategy.forwardWhenOffline || offline) {
          return RoutingDecision(
              action: 'forward',
              forwardTo: rule.forwardTo,
              explanation: 'Rule "${rule.name}": forward (${rule.strategy.name})');
        }
        continue;
      case RoutingStrategy.ringSelected:
        final targets =
            active.where((d) => rule.deviceIds.contains(d.id)).map((d) => d.id).toList();
        if (targets.isEmpty) continue;
        return RoutingDecision(
            action: 'ring',
            ringDeviceIds: targets,
            explanation: 'Rule "${rule.name}": ring selected devices');
      case RoutingStrategy.sequential:
        final targets =
            active.where((d) => rule.deviceIds.contains(d.id)).map((d) => d.id).toList();
        if (targets.isEmpty) continue;
        return RoutingDecision(
            action: 'ring',
            ringDeviceIds: [targets.first],
            explanation: 'Rule "${rule.name}": sequential ring, first device "${targets.first}"');
      case RoutingStrategy.ringAll:
      case RoutingStrategy.simultaneous:
      case RoutingStrategy.humanFirst:
      case RoutingStrategy.aiOverflow:
        if (active.isEmpty) {
          if (rule.strategy == RoutingStrategy.aiOverflow) {
            return RoutingDecision(
                action: 'ai-agent',
                explanation: 'Rule "${rule.name}": no humans available -> AI overflow');
          }
          continue;
        }
        return RoutingDecision(
            action: 'ring',
            ringDeviceIds: active.map((d) => d.id).toList(),
            explanation: 'Rule "${rule.name}": ring all active devices');
    }
  }
  return const RoutingDecision(
      action: 'voicemail', explanation: 'No rule matched -> voicemail fallback');
}
