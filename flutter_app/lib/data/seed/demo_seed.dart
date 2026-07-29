/// Deterministic fictional demo data.
///
/// Every phone number uses the fictional +1-XXX-555-01XX style range;
/// every domain is .example; every record is labelled demo. No real
/// personal data appears anywhere in this file.
library;

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/models/models2.dart';
import '../../engines/routing/routing.dart';
import '../repositories/app_repository.dart';

const _first = [
  'Avery',
  'Jordan',
  'Riley',
  'Morgan',
  'Casey',
  'Quinn',
  'Reese',
  'Skyler',
  'Dakota',
  'Rowan',
  'Emerson',
  'Finley',
  'Harper',
  'Kendall',
  'Logan',
  'Marlow',
  'Nico',
  'Oakley',
  'Parker',
  'Sage',
];
const _last = [
  'Abbott',
  'Barlow',
  'Calder',
  'Dorsey',
  'Ellison',
  'Fairbank',
  'Granger',
  'Holloway',
  'Ingram',
  'Jessup',
  'Keating',
  'Landry',
  'Merritt',
  'Norwood',
  'Osgood',
  'Prescott',
  'Quimby',
  'Redfern',
  'Sutton',
  'Thatcher',
];
const _companies = [
  'Summit Roofing Group',
  'BlueOak Exteriors',
  'Cardinal Storm Repair',
  'Lakeside Home Services',
  'IronGate Contracting',
  'Prairie Wind Roofing',
  'Beacon Restoration',
  'Northline Gutters',
  'Redstone Builders',
  'Harbor Exteriors',
  'TrueSpan Roofing',
  'Vertex Home Pros',
  'Copperleaf Siding',
  'Stonebridge Repair',
  'Meridian Roofworks',
  'Pinnacle Storm Team',
  'Clearwater Exteriors',
  'Foxglove Contracting',
  'Granite Peak Roofing',
  'Silverbirch Homes',
];

String _phoneFor(int i) =>
    '+1${(214 + (i % 7) * 101).toString().padLeft(3, '0')}555${(100 + i).toString().padLeft(4, '0')}';

AppState buildDemoSeed() {
  final now = DateTime.now();

  final companies = <Company>[];
  for (var i = 0; i < _companies.length; i++) {
    companies.add(
      Company(
        id: 'co_seed$i',
        name: _companies[i],
        domain:
            '${_companies[i].toLowerCase().replaceAll(RegExp('[^a-z]'), '')}.example',
        industry: i % 3 == 0 ? 'Roofing' : 'Home Services',
      ),
    );
  }

  final contacts = <Contact>[];
  for (var i = 0; i < 80; i++) {
    contacts.add(
      Contact(
        id: 'ct_seed$i',
        firstName: _first[i % _first.length],
        lastName: _last[(i ~/ _first.length * 7 + i) % _last.length],
        companyId: companies[i % companies.length].id,
        jobTitle: i % 4 == 0 ? 'Owner' : 'Manager',
        phones: [PhoneEntry(label: 'mobile', e164: _phoneFor(i))],
        emails: ['demo.contact$i@mail.example'],
        tags: i >= 40
            ? const ['truuowner-buyer', 'data-sales']
            : i % 5 == 0
            ? const ['storm-lead']
            : const ['inbound'],
        timeZone: i % 2 == 0 ? 'America/Chicago' : 'America/New_York',
        dnc: i == 24 || i == 49,
        smsOptOut: i == 29,
        favorite: i < 4,
        notes: i % 10 == 0 ? 'Prefers afternoon calls. (Demo note)' : '',
        createdAt: now.subtract(Duration(days: 90 - i)),
        updatedAt: now.subtract(Duration(days: i % 30)),
      ),
    );
  }

  final numbers = <PowerlineNumber>[
    const PowerlineNumber(
      id: 'pn_twilio_live',
      e164: '+16052058454',
      label: 'PowerLine Live',
      provider: 'twilio',
      status: 'active',
      isDemo: false,
      a2pStatus: 'trial-restricted',
    ),
    const PowerlineNumber(
      id: 'pn_tx',
      e164: '+12145550100',
      label: 'Sales Line TX',
      a2pStatus: 'demo-unregistered',
    ),
    const PowerlineNumber(
      id: 'pn_mo',
      e164: '+13145550101',
      label: 'Storm Line MO',
    ),
    const PowerlineNumber(
      id: 'pn_main',
      e164: '+14695550102',
      label: 'Main Business',
    ),
    const PowerlineNumber(
      id: 'pn_tf',
      e164: '+18885550103',
      label: 'Toll-Free Demo',
      tollFreeStatus: 'unverified',
    ),
  ];

  final conversations = <Conversation>[];
  final messages = <Message>[];
  for (var i = 0; i < 32; i++) {
    final convId = 'cv_seed$i';
    final at = now.subtract(Duration(hours: i * 5));
    conversations.add(
      Conversation(
        id: convId,
        contactId: contacts[i].id,
        remoteE164: _phoneFor(i),
        powerlineNumberId: numbers[i % numbers.length].id,
        unreadCount: i % 4 == 0 ? 1 : 0,
        pinned: i == 0,
        lastMessageAt: at,
      ),
    );
    final thread = <(CallDirection, String, MessageState)>[
      (
        CallDirection.outbound,
        'Hi ${contacts[i].firstName}, this is the Powerline demo — free roof inspection after the storms. Interested? (Fictional)',
        MessageState.delivered,
      ),
      (
        CallDirection.inbound,
        'Maybe — what times do you have?',
        MessageState.read,
      ),
      (
        CallDirection.outbound,
        'Tuesday 10am or Thursday 2pm. Which works better?',
        i % 6 == 5 ? MessageState.failed : MessageState.delivered,
      ),
    ];
    for (var t = 0; t < thread.length; t++) {
      messages.add(
        Message(
          id: 'ms_seed${i}_$t',
          conversationId: convId,
          direction: thread[t].$1,
          body: thread[t].$2,
          state: thread[t].$3,
          createdAt: at.add(Duration(minutes: t * 4)),
        ),
      );
    }
  }

  final calls = <CallRecord>[];
  final handoffs = <HandoffEvent>[];
  for (var i = 0; i < 64; i++) {
    final started = now.subtract(Duration(hours: i * 3 + 1));
    final inbound = i % 3 == 0;
    final answered = i % 4 != 3;
    final isAi = i % 6 == 0;
    final id = 'cl_seed$i';
    calls.add(
      CallRecord(
        id: id,
        direction: inbound ? CallDirection.inbound : CallDirection.outbound,
        contactId: contacts[i % contacts.length].id,
        remoteE164: _phoneFor(i % 80),
        powerlineNumberId: numbers[i % numbers.length].id,
        agentKind: isAi ? AgentKind.ai : AgentKind.human,
        aiAgentId: isAi ? 'ag_seed0' : null,
        campaignId: i % 5 == 0 ? 'cp_seed0' : null,
        startedAt: started,
        answeredAt: answered ? started.add(const Duration(seconds: 9)) : null,
        endedAt: started.add(Duration(seconds: answered ? 150 + i : 25)),
        durationSeconds: answered ? 140 + i : 0,
        disposition: answered
            ? (i % 5 == 0 ? 'appointment-set' : 'contacted')
            : (inbound ? 'missed' : 'no-answer'),
        finalState: answered
            ? CallState.completed
            : (inbound ? CallState.voicemail : CallState.noAnswer),
        handoffEventIds: i == 6
            ? const ['ho_seed0']
            : (i == 12 ? const ['ho_seed1'] : const []),
      ),
    );
  }
  handoffs.addAll([
    HandoffEvent(
      id: 'ho_seed0',
      callRecordId: 'cl_seed6',
      kind: HandoffKind.aiEscalation,
      reason: 'Caller asked for a human (demo)',
      fromParty: 'ai:Roofing Appointment Assistant',
      toParty: 'human:demo-operator',
      whisperSummary:
          'Caller wants scheduling flexibility; interested but busy weekdays.',
      createdAt: now.subtract(const Duration(hours: 19)),
    ),
    HandoffEvent(
      id: 'ho_seed1',
      callRecordId: 'cl_seed12',
      kind: HandoffKind.humanToAi,
      reason: 'Routine confirmation handed to AI (demo)',
      fromParty: 'human:demo-operator',
      toParty: 'ai:Appointment Confirmation Assistant',
      createdAt: now.subtract(const Duration(hours: 37)),
    ),
  ]);

  final voicemails = <Voicemail>[
    for (var i = 0; i < 8; i++)
      Voicemail(
        id: 'vm_seed$i',
        callRecordId: i < 4 ? 'cl_seed${i * 4 + 3}' : null,
        remoteE164: _phoneFor(i),
        durationSeconds: 18 + i * 6,
        transcript: i % 2 == 0
            ? 'Hi, calling back about the roof estimate — please give me a ring. [Simulated transcript]'
            : '',
        transcriptConfidence: i % 2 == 0 ? 0.93 : 0,
        read: i > 4,
        createdAt: now.subtract(Duration(hours: 6 * i + 2)),
      ),
  ];

  final campaigns = <Campaign>[
    Campaign(
      id: 'cp_seed0',
      name: 'Roofing Inspection - Texas',
      description: 'Free inspection offers for storm-affected TX areas (demo).',
      offer: 'Free 30-minute roof inspection',
      industry: 'Roofing',
      status: CampaignStatus.active,
      timeZone: 'America/Chicago',
      assignedNumberIds: const ['pn_tx'],
      assignedAgentIds: const ['ag_seed0'],
      leadContactIds: [for (var i = 0; i < 30; i++) 'ct_seed$i'],
      callScript:
          'Hi {firstName}, this is {agent} with the demo roofing team...',
      messageTemplates: const [
        'Hi {firstName}, free roof inspection this week — interested?',
      ],
      objectionLibrary: const {
        'too busy':
            'Totally understand — the inspection takes 30 minutes and you do not need to be home.',
        'price concern':
            'The inspection itself is free, and there is no obligation.',
      },
      createdAt: now.subtract(const Duration(days: 21)),
    ),
    Campaign(
      id: 'cp_seed1',
      name: 'Storm Restoration - Missouri',
      status: CampaignStatus.active,
      industry: 'Restoration',
      assignedNumberIds: const ['pn_mo'],
      leadContactIds: [for (var i = 30; i < 55; i++) 'ct_seed$i'],
      createdAt: now.subtract(const Duration(days: 14)),
    ),
    Campaign(
      id: 'cp_seed2',
      name: 'Home Services Follow-up',
      status: CampaignStatus.paused,
      leadContactIds: [for (var i = 55; i < 70; i++) 'ct_seed$i'],
      createdAt: now.subtract(const Duration(days: 10)),
    ),
    Campaign(
      id: 'cp_seed3',
      name: 'Missed Lead Reactivation',
      status: CampaignStatus.draft,
      leadContactIds: [for (var i = 70; i < 80; i++) 'ct_seed$i'],
      createdAt: now.subtract(const Duration(days: 5)),
    ),
    Campaign(
      id: 'cp_seed4',
      name: 'Demo Communications Campaign',
      description: 'Pure demo campaign for showcasing Powerline.',
      status: CampaignStatus.active,
      leadContactIds: [for (var i = 0; i < 12; i++) 'ct_seed$i'],
      createdAt: now.subtract(const Duration(days: 2)),
    ),
    Campaign(
      id: 'cp_data',
      name: 'TruuOwner Data Buyers',
      description:
          'Qualify buyers by audience, geography, volume, fields, and delivery date.',
      offer: 'CRM-ready homeowner records with clear field definitions',
      industry: 'Data Sales',
      status: CampaignStatus.active,
      timeZone: 'America/New_York',
      assignedNumberIds: const ['pn_twilio_live'],
      assignedAgentIds: const ['ag_data'],
      leadContactIds: [for (var i = 40; i < 80; i++) 'ct_seed$i'],
      callScript:
          'Before we talk record count, who exactly are you trying to reach, where, and what makes a record usable for your team?',
      messageTemplates: const [
        'Hi {firstName}, I can map the right homeowner audience, fields, geography, and volume before you spend on the wrong records.',
      ],
      objectionLibrary: const {
        'too expensive':
            'Let us price the usable records and targeting—not a pile of rows your reps cannot sell.',
        'need a sample':
            'I can walk you through the fields, filters, suppression, and delivery format first.',
      },
      createdAt: now.subtract(const Duration(days: 3)),
    ),
  ];

  final deals = <PipelineDeal>[
    for (var i = 0; i < 14; i++)
      PipelineDeal(
        id: 'dl_seed$i',
        contactId: contacts[i * 3].id,
        campaignId: i % 2 == 0 ? 'cp_seed0' : 'cp_seed1',
        stage: PipelineStage.values[i % 9],
        value: 4500.0 + i * 750,
        expectedClose: now.add(Duration(days: 7 + i * 3)),
        nextAction: 'Follow up call',
      ),
  ];

  final appointments = <Appointment>[
    for (var i = 0; i < 6; i++)
      Appointment(
        id: 'ap_seed$i',
        contactId: contacts[i * 5].id,
        campaignId: 'cp_seed0',
        startsAt: now.add(Duration(days: i + 1, hours: 10 - now.hour)),
        kind: 'roof-inspection',
        address: '${100 + i} Demo Lane, Springfield (fictional)',
        confirmed: i % 2 == 0,
        status: AppointmentStatus.scheduled,
      ),
  ];

  final callbacks = <CallbackTask>[
    for (var i = 0; i < 5; i++)
      CallbackTask(
        id: 'cb_seed$i',
        contactId: contacts[i * 7 + 1].id,
        campaignId: 'cp_seed0',
        dueAt: now.add(Duration(hours: 4 + i * 8)),
        reason: 'Asked to call back later (demo)',
      ),
  ];

  final agents = <AiAgent>[
    const AiAgent(
      id: 'ag_seed0',
      name: 'Roofing Appointment Assistant',
      description: 'Books inspection appointments for roofing campaigns.',
      role: 'outbound',
      voiceProvider: 'elevenlabs:arpita-bb',
      greeting:
          'Hi! I am an automated assistant for the demo roofing team. This call is simulated.',
      systemPrompt:
          'You book roof inspection appointments. Always disclose you are an AI.',
      qualificationGoals: [
        'homeowner',
        'storm-affected area',
        'roof age > 8 years',
      ],
      assignedCampaignIds: ['cp_seed0'],
      assignedNumberIds: ['pn_tx'],
    ),
    const AiAgent(
      id: 'ag_seed1',
      name: 'Missed Call Receptionist',
      description: 'Answers when humans miss inbound calls.',
      role: 'inbound',
      greeting:
          'Thanks for calling! Our team is unavailable — I am the automated demo assistant.',
    ),
    const AiAgent(
      id: 'ag_seed2',
      name: 'Appointment Confirmation Assistant',
      role: 'outbound',
      greeting:
          'Hello, this is the automated demo assistant confirming your appointment.',
    ),
    const AiAgent(
      id: 'ag_seed3',
      name: 'After-Hours Receptionist',
      role: 'inbound',
      greeting:
          'You have reached us after hours. I am the automated demo assistant.',
    ),
    const AiAgent(
      id: 'ag_seed4',
      name: 'Demo AI Agent',
      description: 'Scripted local demo agent.',
      role: 'inbound',
      greeting:
          'Hello! This is the Powerline demo AI agent. This conversation is simulated.',
    ),
    const AiAgent(
      id: 'ag_data',
      name: 'TruuOwner Buyer Qualifier',
      description:
          'Qualifies data buyers before a human rep scopes volume and pricing.',
      role: 'outbound',
      voiceProvider: 'elevenlabs:arpita-bb',
      greeting:
          'Hi, this is the automated TruuOwner qualification assistant. I will ask a few questions before connecting you with a data specialist.',
      systemPrompt:
          'Identify audience, geography, volume, required fields, use case, delivery date, CRM, and budget. Never promise an accuracy rate or final price. Escalate qualified buyers to a human.',
      qualificationGoals: [
        'target audience',
        'states or ZIP codes',
        'record volume',
        'required fields',
        'CRM and campaign type',
        'delivery date',
        'budget range',
      ],
      assignedCampaignIds: ['cp_data'],
      assignedNumberIds: ['pn_twilio_live'],
      handoffDestination: 'ring-group:data-sales',
    ),
  ];

  final devices = <DeviceRecord>[
    DeviceRecord(
      id: 'dv_this',
      name: 'This device',
      type: DeviceType.windowsDesktop,
      lastActive: now,
      isThisDevice: true,
    ),
    DeviceRecord(
      id: 'dv_mac',
      name: 'Demo MacBook',
      type: DeviceType.macDesktop,
      lastActive: now.subtract(const Duration(minutes: 12)),
    ),
    DeviceRecord(
      id: 'dv_android',
      name: 'Demo Pixel',
      type: DeviceType.androidPhone,
      lastActive: now.subtract(const Duration(minutes: 3)),
    ),
    DeviceRecord(
      id: 'dv_iphone',
      name: 'Demo iPhone',
      type: DeviceType.iphone,
      lastActive: now.subtract(const Duration(hours: 2)),
    ),
    DeviceRecord(
      id: 'dv_web',
      name: 'Demo web session',
      type: DeviceType.webSession,
      lastActive: now.subtract(const Duration(days: 1)),
      ringEnabled: false,
    ),
  ];

  final routingRules = <RoutingRule>[
    const RoutingRule(
      id: 'rr_hours',
      name: 'Business hours: ring all',
      strategy: RoutingStrategy.ringAll,
      businessHoursOnly: true,
      afterHoursAction: 'ai-agent',
      priority: 0,
    ),
    const RoutingRule(
      id: 'rr_overflow',
      name: 'AI overflow when nobody available',
      strategy: RoutingStrategy.aiOverflow,
      priority: 1,
    ),
    const RoutingRule(
      id: 'rr_vm',
      name: 'Fallback to voicemail',
      strategy: RoutingStrategy.directToVoicemail,
      priority: 9,
    ),
  ];

  final integrations = <IntegrationCard>[
    const IntegrationCard(
      id: 'ic_demo_tel',
      provider: 'Demo provider',
      category: 'telephony',
      state: ProviderState.activeDemo,
      capabilities: ['simulated calls', 'simulated inbound'],
      missingCapabilities: ['real PSTN', 'E911'],
    ),
    const IntegrationCard(
      id: 'ic_twilio',
      provider: 'Twilio',
      category: 'telephony',
      configFields: ['Account SID', 'Auth Token', 'TwiML App SID'],
      missingCapabilities: ['everything until configured'],
    ),
    const IntegrationCard(
      id: 'ic_signalmash',
      provider: 'SignalMash',
      category: 'telephony',
      configFields: ['API Key', 'Trunk credentials'],
    ),
    const IntegrationCard(
      id: 'ic_vonage',
      provider: 'Vonage',
      category: 'telephony',
      configFields: ['API Key', 'API Secret', 'Application ID'],
    ),
    const IntegrationCard(
      id: 'ic_sip',
      provider: 'SIP provider',
      category: 'telephony',
      configFields: ['Server', 'Username', 'Password'],
    ),
    const IntegrationCard(
      id: 'ic_asterisk',
      provider: 'Asterisk',
      category: 'telephony',
      configFields: ['AMI host', 'AMI user', 'AMI secret', 'ARI app'],
    ),
    const IntegrationCard(
      id: 'ic_vicidial',
      provider: 'VICIdial',
      category: 'telephony',
      configFields: ['Server URL', 'API user', 'API pass', 'Agent login'],
      state: ProviderState.error,
      lastError: 'Demo seeded error: connection test never run',
    ),
    const IntegrationCard(
      id: 'ic_extdialer',
      provider: 'External dialer',
      category: 'telephony',
      state: ProviderState.configured,
      capabilities: ['tel: URI handoff'],
    ),
    const IntegrationCard(
      id: 'ic_demo_msg',
      provider: 'Demo provider',
      category: 'messaging',
      state: ProviderState.activeDemo,
      capabilities: ['simulated SMS', 'simulated replies', 'opt-out keywords'],
    ),
    const IntegrationCard(
      id: 'ic_tw_msg',
      provider: 'Twilio',
      category: 'messaging',
      configFields: ['Account SID', 'Auth Token', 'Messaging Service SID'],
    ),
    const IntegrationCard(
      id: 'ic_sm_msg',
      provider: 'SignalMash',
      category: 'messaging',
      configFields: ['API Key', '10DLC campaign ID'],
    ),
    const IntegrationCard(
      id: 'ic_vo_msg',
      provider: 'Vonage',
      category: 'messaging',
      configFields: ['API Key', 'API Secret'],
    ),
    const IntegrationCard(
      id: 'ic_webhook_msg',
      provider: 'Generic webhook',
      category: 'messaging',
      configFields: ['Webhook URL', 'Signing secret'],
    ),
    const IntegrationCard(
      id: 'ic_anthropic',
      provider: 'Anthropic',
      category: 'ai',
      configFields: ['API key'],
    ),
    const IntegrationCard(
      id: 'ic_openai',
      provider: 'OpenAI',
      category: 'ai',
      configFields: ['API key'],
    ),
    const IntegrationCard(
      id: 'ic_gemini',
      provider: 'Gemini',
      category: 'ai',
      configFields: ['API key'],
    ),
    const IntegrationCard(
      id: 'ic_oai_compat',
      provider: 'OpenAI-compatible endpoint',
      category: 'ai',
      configFields: ['Base URL', 'API key', 'Model name'],
    ),
    const IntegrationCard(
      id: 'ic_local_llm',
      provider: 'Local model',
      category: 'ai',
      configFields: ['Endpoint URL'],
    ),
    const IntegrationCard(
      id: 'ic_mock_ai',
      provider: 'Mock AI',
      category: 'ai',
      state: ProviderState.activeDemo,
      capabilities: ['scripted local conversations'],
    ),
    const IntegrationCard(
      id: 'ic_mock_stt',
      provider: 'Mock transcription',
      category: 'transcription',
      state: ProviderState.activeDemo,
      capabilities: ['deterministic demo transcripts'],
    ),
    const IntegrationCard(
      id: 'ic_gcal',
      provider: 'Google Calendar',
      category: 'calendar',
      configFields: ['OAuth connection'],
    ),
    const IntegrationCard(
      id: 'ic_calcom',
      provider: 'Cal.com',
      category: 'calendar',
      configFields: ['API key'],
    ),
    const IntegrationCard(
      id: 'ic_mock_cal',
      provider: 'Mock calendar',
      category: 'calendar',
      state: ProviderState.activeDemo,
    ),
    const IntegrationCard(
      id: 'ic_internal_crm',
      provider: 'Internal CRM',
      category: 'crm',
      state: ProviderState.activeDemo,
    ),
    const IntegrationCard(
      id: 'ic_hubspot',
      provider: 'HubSpot',
      category: 'crm',
      configFields: ['Private app token'],
    ),
    const IntegrationCard(
      id: 'ic_zoho',
      provider: 'Zoho',
      category: 'crm',
      configFields: ['OAuth connection'],
    ),
  ];

  final dnc = <DncRecord>[
    DncRecord(
      id: 'dnc_seed0',
      e164: _phoneFor(24),
      reason: 'requested no contact (demo)',
      createdAt: now,
    ),
    DncRecord(
      id: 'dnc_seed1',
      e164: _phoneFor(49),
      reason: 'requested no contact (demo)',
      createdAt: now,
    ),
    DncRecord(
      id: 'dnc_seed2',
      e164: _phoneFor(74),
      reason: 'imported DNC list (demo)',
      source: 'import',
      createdAt: now,
    ),
  ];

  return AppState(
    contacts: contacts,
    companies: companies,
    numbers: numbers,
    conversations: conversations,
    messages: messages,
    calls: calls,
    voicemails: voicemails,
    campaigns: campaigns,
    deals: deals,
    appointments: appointments,
    callbacks: callbacks,
    agents: agents,
    devices: devices,
    routingRules: routingRules,
    handoffs: handoffs,
    dnc: dnc,
    smsSuppression: [_phoneFor(29)],
    integrations: integrations,
    notifications: [
      AppNotification(
        id: 'nt_seed0',
        kind: 'provider',
        title: 'Demo mode active',
        body:
            'No live telecom provider is connected. All calls and messages are simulated.',
        at: now,
      ),
    ],
    businessHours: const BusinessHours(),
    settings: const {
      'companyName': 'AZD Global Enterprises Inc. (demo workspace)',
      'defaultCountry': 'US',
      'defaultTimeZone': 'America/Chicago',
      'defaultCallerId': 'pn_main',
      'theme': 'dark',
      'aiDisclosure': 'This call may be handled by an automated assistant.',
      'demoMode': 'true',
    },
    activityLog: ['${now.toIso8601String()} demo data seeded'],
  );
}
