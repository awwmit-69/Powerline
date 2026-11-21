// PUBLIC function /voice-token — issues a short-lived Twilio Voice access token
// to a signed-in agent.
// POST (form-encoded): session=<session from /auth-verify>
// (Sent in the body, not a header, so browsers make a simple CORS request.)
// Identity = agent id. Outgoing calls go through TWIML_APP_SID (/voice-outbound);
// incoming calls ring the agent's registered browser via <Client>.

exports.handler = function (context, event, callback) {
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const { verify, jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);

  if (!originAllowed(context, event)) {
    return callback(null, jsonResponse(context, event, 403, { error: 'origin_not_allowed' }));
  }

  const payload = verify(event.session, context.SESSION_SECRET);
  if (!payload || !parseAgents(context.AGENTS).has(payload.sub)) {
    return callback(null, jsonResponse(context, event, 401, { error: 'not_signed_in' }));
  }

  const ttl = Math.min(parseInt(context.VOICE_TOKEN_TTL_SECONDS || '3600', 10), 3600);
  const AccessToken = Twilio.jwt.AccessToken;
  const token = new AccessToken(
    context.TWILIO_ACCOUNT_SID,
    context.TWILIO_API_KEY_SID,
    context.TWILIO_API_KEY_SECRET,
    { identity: payload.sub, ttl },
  );
  token.addGrant(
    new AccessToken.VoiceGrant({
      outgoingApplicationSid: context.TWIML_APP_SID,
      incomingAllow: true,
    }),
  );
  console.log(`VOICE_TOKEN agent=${payload.sub} ttl=${ttl}`);
  return callback(null, jsonResponse(context, event, 200, { token: token.toJwt(), identity: payload.sub, ttl }));
};
