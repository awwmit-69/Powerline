// Do not expose an unauthenticated Twilio Functions SMS relay publicly.
// Outbound SMS must be sent from an authenticated PowerLine backend with
// authorization, consent/suppression checks, and rate limits. The old
// implementation allowed arbitrary callers to send billable SMS from the
// Twilio account and must not be deployed as a public function.
exports.handler = function (context, event, callback) {
  const response = new Twilio.Response();
  response.appendHeader('Content-Type', 'application/json');
  response.setStatusCode(503);
  response.setBody({
    error: 'SMS sending disabled pending authenticated server integration',
  });
  return callback(null, response);
};
