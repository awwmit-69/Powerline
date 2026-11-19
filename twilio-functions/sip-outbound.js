// PROTECTED function /sip-outbound — call handler of SIP Domain
// azdpowerline.sip.twilio.com (Zoiper/Bria softphones).
// Caller must be an allowed SIP user (SIP_USERS) on our own SIP domain; the
// domain itself already requires credential-list authentication.

exports.handler = function (context, event, callback) {
  const { checkDestination, rejectTwiml } = require(Runtime.getFunctions()['dialrules'].path);
  const twiml = new Twilio.twiml.VoiceResponse();

  const domain = String(context.SIP_DOMAIN || '').toLowerCase();
  const allowedUsers = String(context.SIP_USERS || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  const from = String(event.From || '').toLowerCase();
  const m = from.match(/^sip:([^@;]+)@([^;>]+)/);
  const user = m && m[1];
  const host = m && m[2];
  const label = domain.split('.sip.')[0];
  const hostOk = host && label && host.startsWith(`${label}.sip.`) && host.endsWith('twilio.com');
  if (!user || !hostOk || !allowedUsers.includes(user)) {
    console.log(`SIP_OUT reject=unauthorized_from:${user || 'none'}`);
    return callback(null, rejectTwiml(twiml, 'This line is not authorized to place calls.'));
  }

  const toUser = (String(event.To || '').match(/^sip:([^@;]+)@/i) || [])[1] || '';
  const result = checkDestination(toUser, context.CALLER_ID);
  if (!result.ok) {
    console.log(`SIP_OUT user=${user} reject=${result.reason}`);
    return callback(null, rejectTwiml(twiml, result.message));
  }

  console.log(`SIP_OUT user=${user} npa=${result.e164.slice(2, 5)}`);
  const dial = twiml.dial({
    callerId: context.CALLER_ID,
    answerOnBridge: true,
    timeout: 45,
    timeLimit: parseInt(context.MAX_CALL_SECONDS || '3600', 10),
  });
  dial.number(result.e164);
  return callback(null, twiml);
};
