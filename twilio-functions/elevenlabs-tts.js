exports.handler = async function (context, event, callback) {
  const response = new Twilio.Response();
  response.appendHeader('Access-Control-Allow-Origin', '*');
  response.appendHeader('Access-Control-Allow-Headers', 'Content-Type');
  response.appendHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');

  if (event.request && event.request.method === 'OPTIONS') {
    response.setStatusCode(204);
    return callback(null, response);
  }

  const apiKey = context.ELEVENLABS_API_KEY;
  const voiceId = context.ELEVENLABS_VOICE_ID;
  const text = String(event.text || '').trim();

  if (!apiKey || !voiceId) {
    response.setStatusCode(503);
    response.appendHeader('Content-Type', 'application/json');
    response.setBody({ error: 'ElevenLabs voice is not configured' });
    return callback(null, response);
  }
  if (!text || text.length > 1200) {
    response.setStatusCode(400);
    response.appendHeader('Content-Type', 'application/json');
    response.setBody({ error: 'text must contain 1 to 1200 characters' });
    return callback(null, response);
  }

  try {
    const tts = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
      {
        method: 'POST',
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
        },
        body: JSON.stringify({
          text,
          model_id: 'eleven_flash_v2_5',
          voice_settings: {
            stability: 0.55,
            similarity_boost: 0.82,
            style: 0.25,
            use_speaker_boost: true,
          },
        }),
      },
    );
    if (!tts.ok) {
      throw new Error(`ElevenLabs returned ${tts.status}`);
    }

    const audio = Buffer.from(await tts.arrayBuffer());
    response.setStatusCode(200);
    response.appendHeader('Content-Type', 'audio/mpeg');
    response.appendHeader('Cache-Control', 'no-store');
    response.setBody(audio);
    return callback(null, response);
  } catch (error) {
    response.setStatusCode(502);
    response.appendHeader('Content-Type', 'application/json');
    response.setBody({ error: error.message || 'Voice generation failed' });
    return callback(null, response);
  }
};
