// PUBLIC function /auth-start — begins agent sign-in with a Twilio Verify SMS code.
// POST (form-encoded): agent=<agentId>
// Only agents listed in AGENTS receive a code. The response is identical for
// unknown agents to avoid account enumeration. Twilio Verify enforces its own
// send rate limits and Fraud Guard.
//
// Env: AGENTS, VERIFY_SERVICE_SID, TWILIO_ACCOUNT_SID, TWILIO_API_KEY_SID,
//      TWILIO_API_KEY_SECRET, ALLOWED_ORIGINS

exports.handler = async function (context, event, callback) {
  const { parseAgents, parsePins } = require(Runtime.getFunctions()['dialrules'].path);
  const { jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);

  if (!originAllowed(context, event)) {
    return callback(null, jsonResponse(context, event, 403, { error: 'origin_not_allowed' }));
  }

  const agentId = String(event.agent || '').trim().toLowerCase();
  const agents = parseAgents(context.AGENTS);
  const phone = agents.get(agentId);

  // Primary sign-in: PowerLine PIN (no SMS needed). The app then asks for the PIN.
  if (phone && parsePins(context.AGENT_PINS, context.AGENTS).has(agentId)) {
    console.log(`AUTH_START agent=${agentId} method=pin`);
    return callback(null, jsonResponse(context, event, 200, { sent: false, fallback: 'pin' }));
  }

  if (phone) {
    try {
      const client = require('twilio')(context.TWILIO_API_KEY_SID, context.TWILIO_API_KEY_SECRET, {
        accountSid: context.TWILIO_ACCOUNT_SID,
      });
      await client.verify.v2
        .services(context.VERIFY_SERVICE_SID)
        .verifications.create({ to: phone, channel: 'sms' });
      console.log(`AUTH_START agent=${agentId} sent=1`);
    } catch (err) {
      // Log status only; never log phone numbers or codes.
      console.log(`AUTH_START agent=${agentId} error=${err && err.status} code=${err && err.code}`);
      return callback(null, jsonResponse(context, event, 429, {
        error: 'unable_to_send_code',
        code: (err && err.code) || null,
        status: (err && err.status) || null,
        // Non-secret hint: AGENT_PINS is set but has no valid PIN for this agent.
        pinFormatInvalid: Boolean(context.AGENT_PINS) || undefined,
      }));
    }
  } else {
    console.log('AUTH_START unknown_agent');
    await new Promise((r) => setTimeout(r, 400));
  }
  return callback(null, jsonResponse(context, event, 200, { sent: true }));
};
