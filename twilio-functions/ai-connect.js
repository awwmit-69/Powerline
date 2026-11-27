// PROTECTED function /ai-connect — answer URL for calls started by /ai-call.
// Human answered -> hand the call to the ElevenLabs agent (outbound mode).
// Voicemail/fax -> hang up (no AI voicemail drops).

exports.handler = async function (context, event, callback) {
  const ai = require(Runtime.getFunctions()['ai'].path);
  const twiml = new Twilio.twiml.VoiceResponse();

  const answeredBy = String(event.AnsweredBy || '');
  if (answeredBy.startsWith('machine') || answeredBy === 'fax') {
    console.log(`AI_CONNECT sid=${event.CallSid} skip=${answeredBy}`);
    twiml.hangup();
    return callback(null, twiml);
  }

  // mode=confirm comes from /confirm-run (day-before confirmation/rebook call).
  const confirm = event.mode === 'confirm' && event.event_id;
  const xml = await ai.registerCall(context, {
    from: event.From || context.CALLER_ID,
    to: event.To,
    direction: 'outbound',
    vars: {
      call_direction: confirm ? 'confirm' : 'outbound',
      business_number: context.CALLER_ID,
      business_name: context.BUSINESS_NAME || 'AZD Global',
      lead_first_name: event.first_name || 'there',
      vertical: event.vertical || 'general',
      caller_number: event.To || 'unknown',
      event_id: confirm ? event.event_id : 'none',
      appointment_time: confirm ? event.appointment_time || 'your appointment' : 'none',
    },
  });
  if (!xml) {
    console.log(`AI_CONNECT sid=${event.CallSid} fail=register`);
    twiml.say({ voice: 'Polly.Joanna' }, 'Sorry, we are having trouble connecting. We will try you again later. Goodbye.');
    twiml.hangup();
    return callback(null, twiml);
  }
  console.log(`AI_CONNECT sid=${event.CallSid} ok vertical=${event.vertical || 'general'}`);
  return callback(null, ai.rawTwimlResponse(xml));
};
