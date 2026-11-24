// PROTECTED function /sip-inbound — Voice handler of the PowerLine number.
// Rings, in parallel, every registered softphone (SIP_USERS on SIP_DOMAIN) and
// every signed-in PowerLine browser agent (<Client> identities from AGENTS).
// First device to answer wins. If nobody answers: the ElevenLabs AI agent picks up
// (when ELEVENLABS_* is set and AI_INBOUND is not off), else voicemail.

exports.handler = function (context, event, callback) {
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const twiml = new Twilio.twiml.VoiceResponse();
  const say = (text) => twiml.say({ voice: 'Polly.Joanna' }, text);

  const domain = context.SIP_DOMAIN; // global URI, no edge
  const sipUsers = String(context.SIP_USERS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  const clientAgents = [...parseAgents(context.AGENTS).keys()];

  // Third pass: voicemail finished recording.
  if (event.step === 'vm-done') {
    console.log(`VOICEMAIL sid=${event.CallSid} rec=${event.RecordingSid || 'none'} dur=${event.RecordingDuration || 0}`);
    say('Thank you. Your message has been recorded. Goodbye.');
    twiml.hangup();
    return callback(null, twiml);
  }

  // Second pass: <Dial action> after the ring attempt finished.
  if (event.DialCallStatus) {
    console.log(`DIAL_RESULT status=${event.DialCallStatus} sid=${event.CallSid}`);
    if (event.DialCallStatus === 'completed' || event.DialCallStatus === 'answered') {
      twiml.hangup();
      return callback(null, twiml);
    }
    // Nobody picked up: hand the caller to the AI agent if it's configured.
    const ai = require(Runtime.getFunctions()['ai'].path);
    if (ai.inboundEnabled(context)) {
        return ai
          .registerCall(context, {
            from: event.From,
            to: event.To || context.CALLER_ID,
            direction: 'inbound',
            vars: { call_direction: 'inbound', business_number: context.CALLER_ID, lead_first_name: 'there', vertical: 'general', caller_number: String(event.From || '') },
          })
          .then((aiXml) => {
            if (aiXml) {
              console.log(`AI_INBOUND sid=${event.CallSid}`);
              return callback(null, ai.rawTwimlResponse(aiXml));
            }
            return callback(null, voicemail());
          })
          .catch(() => callback(null, voicemail()));
    }
    return callback(null, voicemail());
  }

  function voicemail() {
    const vm = new Twilio.twiml.VoiceResponse();
    vm.say({ voice: 'Polly.Joanna' }, 'Sorry, no one is available to take your call. Please leave a message after the tone.');
    vm.record({
      maxLength: parseInt(context.VM_MAX_SECONDS || '120', 10),
      playBeep: true,
      timeout: 5,
      trim: 'trim-silence',
      action: '/sip-inbound?step=vm-done',
      method: 'POST',
    });
    vm.say({ voice: 'Polly.Joanna' }, 'No message was recorded. Goodbye.');
    vm.hangup();
    return vm;
  }

  if ((!domain || sipUsers.length === 0) && clientAgents.length === 0) {
    console.log('CONFIG_ERROR no SIP_USERS and no AGENTS');
    say('This number is temporarily unavailable. Goodbye.');
    twiml.hangup();
    return callback(null, twiml);
  }

  console.log(`INBOUND sid=${event.CallSid} sip=${sipUsers.length} clients=${clientAgents.length}`);
  const dial = twiml.dial({
    // Answer the caller's leg right away (Twilio plays ringback) so the caller's
    // own carrier can't time out at ~20s before we fall through to Maya/voicemail.
    // Set ANSWER_ON_BRIDGE=true to restore the old "unanswered until picked up" mode.
    timeout: parseInt(context.RING_SECONDS || '20', 10),
    answerOnBridge: String(context.ANSWER_ON_BRIDGE || 'false') === 'true',
    action: '/sip-inbound',
    method: 'POST',
  });
  if (domain) sipUsers.forEach((u) => dial.sip(`sip:${u}@${domain}`));
  clientAgents.forEach((id) => dial.client(id));
  return callback(null, twiml);
};
