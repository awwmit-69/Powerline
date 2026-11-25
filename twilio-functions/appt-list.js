// PUBLIC function /appt-list — PowerLine Appointments screen.
// POST form: session=<agent session>  [ action=cancel  key=slot-… ]
// Lists bookings from 1 day ago forward; action=cancel removes one booking.

exports.handler = async function (context, event, callback) {
  const { parseAgents } = require(Runtime.getFunctions()['dialrules'].path);
  const { verify, jsonResponse, originAllowed } = require(Runtime.getFunctions()['session'].path);
  const appt = require(Runtime.getFunctions()['appt'].path);
  const reply = (status, body) => callback(null, jsonResponse(context, event, status, body));

  if (!originAllowed(context, event)) return reply(403, { error: 'origin_not_allowed' });
  const payload = verify(event.session, context.SESSION_SECRET);
  if (!payload || !parseAgents(context.AGENTS).has(payload.sub)) return reply(401, { error: 'not_signed_in' });

  try {
    if (event.action === 'cancel') {
      const key = String(event.key || '');
      if (!/^slot-\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(key)) return reply(400, { error: 'bad_key' });
      await appt.deleteBooking(context, key);
      console.log(`APPT_CANCEL agent=${payload.sub} key=${key}`);
      return reply(200, { ok: true });
    }
    const since = Date.now() - 24 * 3600 * 1000;
    const items = (await appt.listBookings(context))
      .filter((b) => Date.parse(b.start) >= since)
      .map((b) => ({ ...b, label: appt.label(Date.parse(b.start), b.timezone || appt.config(context).tz) }));
    return reply(200, { appointments: items });
  } catch (err) {
    console.log(`APPT_LIST_FAIL code=${err && err.code}`);
    return reply(500, { error: 'calendar_unavailable' });
  }
};
