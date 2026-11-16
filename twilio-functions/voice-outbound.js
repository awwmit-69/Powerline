// PROTECTED function /voice-outbound — Voice URL of the PowerLine TwiML App.
// Twilio calls this when a signed-in browser agent places a call.
// Caller must be client:<agentId> for an agent in AGENTS (identity comes from
// the server-issued access token). Destination must pass shared dial rules.
// Caller ID is always CALLER_ID (the account's own Twilio number).

exports.handler = function (context, event, callback) {
  const { checkDestination, parseAgents, rejectTwiml } = require(Runtime.getFunctions()['dialrules'].path);
  const twiml = new Twilio.twiml.VoiceResponse();

  const from = String(event.From || event.Caller || '');
  const agentId = from.startsWith('client:') ? from.slice(7).toLowerCase() : '';
  if (!agentId || !parseAgents(context.AGENTS).has(agentId)) {
    console.log('VOICE_OUT reject=unauthorized_agent');
    return callback(null, rejectTwiml(twiml, 'This agent is not authorized to place calls.'));
  }

  const result = checkDestination(event.To, context.CALLER_ID);
  if (!result.ok) {
    console.log(`VOICE_OUT agent=${agentId} reject=${result.reason}`);
    return callback(null, rejectTwiml(twiml, result.message));
  }

  console.log(`VOICE_OUT agent=${agentId} npa=${result.e164.slice(2, 5)}`);
  const dial = twiml.dial({
    callerId: context.CALLER_ID,
    answerOnBridge: true,
    timeout: 45,
    timeLimit: parseInt(context.MAX_CALL_SECONDS || '3600', 10),
  });
  dial.number(result.e164);
  return callback(null, twiml);
};
