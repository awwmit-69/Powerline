exports.handler = function (context, event, callback) {
  const response = new Twilio.twiml.MessagingResponse();
  const body = String(event.Body || '').trim().toLowerCase();

  if (['stop', 'stopall', 'unsubscribe', 'cancel', 'end', 'quit'].includes(body)) {
    response.message(
      'You have been opted out and will not receive further PowerLine messages.',
    );
  }

  callback(null, response);
};
