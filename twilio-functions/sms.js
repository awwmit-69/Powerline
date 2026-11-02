// Retired: this legacy public endpoint had no application authentication.
// Deploy this replacement to the existing Twilio Function to close that surface.
// New sends belong on backend/worker.mjs behind verified identity and number ACLs.
exports.handler = function (_context, _event, callback) {
  const response = new Twilio.Response();
  response.setStatusCode(410);
  response.appendHeader('Content-Type', 'application/json');
  response.appendHeader('Cache-Control', 'no-store');
  response.setBody({error: 'Legacy SMS endpoint retired. Use the authenticated PowerLine API.'});
  return callback(null, response);
};

