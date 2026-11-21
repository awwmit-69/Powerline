// PUBLIC function /auth-start — begins agent sign-in with a Twilio Verify SMS code.
// POST (form-encoded): agent=<agentId>
// Only agents listed in AGENTS receive a code. The response is identical for
// unknown agents to avoid account enumeration. Twilio Verify enforces its own
// send rate limits and Fraud Guard.
//
// Env: AGENTS, VERIFY_SERVICE_SID, TWILIO_ACCOUNT_SID, TWILIO_API_KEY_SID,
//      TWILIO_API_KEY_SECRET, ALLOWED_ORIGINS

exports.handler = async function (context, event, callback) {
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const { jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);

  if (!originAllowed(context, event)) {
    return callback(null, jsonResponse(context, event, 403, { error: 'origin_not_allowed' }));
  }

  const agentId = String(event.agent || '').trim().toLowerCase();
  const agents = parseAgents(context.AGENTS);
  const phone = agents.get(agentId);

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
      console.log(`AUTH_START agent=${agentId} error=${err && err.status}`);
      return callback(null, jsonResponse(context, event, 429, { error: 'unable_to_send_code' }));
    }
  } else {
    console.log('AUTH_START unknown_agent');
    await new Promise((r) => setTimeout(r, 400));
  }
  return callback(null, jsonResponse(context, event, 200, { sent: true }));
};
