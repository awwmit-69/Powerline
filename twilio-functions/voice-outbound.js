// Twilio Function: /voice/outbound (set Visibility = Protected).
// Called by Twilio through the Voice SDK TwiML Application's Voice URL.
// Start with a tightly controlled allowlist for a first live test.
// This is NOT an agent authorization mechanism. Production requires
// authenticated token issuance, agent permissions, and fraud/rate controls.
exports.handler = function (context, event, callback) {
  const twiml = new Twilio.twiml.VoiceResponse();
  const to = String(event.To || "").trim();
  const from = String(context.POWERLINE_FROM_NUMBER || "").trim();
  const permitted = String(context.POWERLINE_TEST_DESTINATIONS || "")
    .split(",")
    .map((number) => number.trim())
    .filter(Boolean);

  // E.164 destination only. No arbitrary SIP/Client routing.
  if (!/^\+[1-9]\d{7,14}$/.test(to) || !permitted.includes(to)) {
    twiml.say("This destination is not approved for PowerLine testing.");
    twiml.hangup();
    return callback(null, twiml);
  }
  if (!/^\+[1-9]\d{7,14}$/.test(from)) {
    twiml.say("PowerLine calling is not configured.");
    twiml.hangup();
    return callback(null, twiml);
  }

  const dial = twiml.dial({
    callerId: from,
    answerOnBridge: true,
    timeout: 30,
  });
  dial.number(to);
  return callback(null, twiml);
};
