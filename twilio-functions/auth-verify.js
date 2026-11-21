// PUBLIC function /auth-verify — completes agent sign-in.
// POST (form-encoded): agent=<agentId>&code=<6-digit code>
// Returns { session, agent, expiresAt } — a signed session used to request
// short-lived voice tokens. Session lifetime: SESSION_TTL_SECONDS (default 12h).

exports.handler = async function (context, event, callback) {
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const { sign, jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);

  if (!originAllowed(context, event)) {
    return callback(null, jsonResponse(context, event, 403, { error: 'origin_not_allowed' }));
  }

  const agentId = String(event.agent || '').trim().toLowerCase();
  const code = String(event.code || '').trim();
  const phone = parseAgents(context.AGENTS).get(agentId);
  const fail = () => callback(null, jsonResponse(context, event, 401, { error: 'invalid_code' }));

  if (!phone || !/^\d{4,10}$/.test(code)) {
    await new Promise((r) => setTimeout(r, 400));
    return fail();
  }

  try {
    const client = require('twilio')(context.TWILIO_API_KEY_SID, context.TWILIO_API_KEY_SECRET, {
      accountSid: context.TWILIO_ACCOUNT_SID,
    });
    const check = await client.verify.v2
      .services(context.VERIFY_SERVICE_SID)
      .verificationChecks.create({ to: phone, code });
    if (check.status !== 'approved') {
      console.log(`AUTH_VERIFY agent=${agentId} status=${check.status}`);
      return fail();
    }
  } catch (err) {
    console.log(`AUTH_VERIFY agent=${agentId} error=${err && err.status}`);
    return fail();
  }

  const ttl = parseInt(context.SESSION_TTL_SECONDS || '43200', 10);
  const session = sign({ sub: agentId }, context.SESSION_SECRET, ttl);
  console.log(`AUTH_VERIFY agent=${agentId} approved`);
  return callback(
    null,
    jsonResponse(context, event, 200, {
      session,
      agent: agentId,
      expiresAt: Math.floor(Date.now() / 1000) + ttl,
    }),
  );
};
