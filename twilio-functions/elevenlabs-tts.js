// Retired until authenticated, authorized and rate-limited TTS is available.
// This legacy function accepted arbitrary billable text without user verification.
exports.handler = function (_context, _event, callback) {
  const response = new Twilio.Response();
  response.setStatusCode(410);
  response.appendHeader('Content-Type', 'application/json');
  response.appendHeader('Cache-Control', 'no-store');
  response.setBody({error: 'Legacy TTS endpoint retired. Authenticated voice generation is not enabled.'});
  return callback(null, response);
};
