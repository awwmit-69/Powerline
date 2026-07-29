exports.handler = async function (context, event, callback) {
  const response = new Twilio.Response();
  response.appendHeader('Access-Control-Allow-Origin', '*');
  response.appendHeader('Access-Control-Allow-Headers', 'Content-Type');
  response.appendHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.appendHeader('Content-Type', 'application/json');

  if (event.request && event.request.method === 'OPTIONS') {
    response.setStatusCode(204);
    return callback(null, response);
  }

  try {
    const payload =
      typeof event === 'string' ? JSON.parse(event) : event || {};
    const to = String(payload.to || '').trim();
    const body = String(payload.body || '').trim();
    const from = String(
      context.POWERLINE_FROM_NUMBER || payload.from || '',
    ).trim();

    if (!to || !from || !body) {
      response.setStatusCode(400);
      response.setBody({ error: 'to, from, and body are required' });
      return callback(null, response);
    }
    if (body.length > 1600) {
      response.setStatusCode(400);
      response.setBody({ error: 'message exceeds 1600 characters' });
      return callback(null, response);
    }

    const client = context.getTwilioClient();
    const message = await client.messages.create({ to, from, body });
    response.setStatusCode(200);
    response.setBody({
      sid: message.sid,
      status: message.status,
      to: message.to,
      from: message.from,
    });
    return callback(null, response);
  } catch (error) {
    response.setStatusCode(500);
    response.setBody({ error: error.message || 'SMS send failed' });
    return callback(null, response);
  }
};
