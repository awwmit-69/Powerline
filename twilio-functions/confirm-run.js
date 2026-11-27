// PUBLIC function /confirm-run — once a day, Maya calls everyone booked for
// TOMORROW (booking time zone) to confirm or rebook. Trigger: the GitHub Actions
// workflow `daily-confirm.yml` (or n8n) with `Authorization: Bearer <CONFIRM_TOKEN>`.
//
// Calls only bookings where the caller agreed to a confirmation call
// (pl_confirm_ok=1), status still "booked", not in DNC_NUMBERS, and only inside
// AI_CALL_HOURS. Optional POST field `dry_run=true` lists without calling.

const crypto = require('crypto');

function safeEqual(a, b) {
  const x = Buffer.from(String(a || ''));
  const y = Buffer.from(String(b || ''));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

exports.handler = async function (context, event, callback) {
  const cal = require(Runtime.getFunctions()['calendar'].path);
  const ai = require(Runtime.getFunctions()['ai'].path);
  const reply = (status, body) => {
    const r = new Twilio.Response();
    r.setStatusCode(status);
    r.appendHeader('Content-Type', 'application/json');
    r.setBody(body);
    return callback(null, r);
  };

  const auth = String(((event.request && event.request.headers) || {}).authorization || '');
  if (!context.CONFIRM_TOKEN || !auth.startsWith('Bearer ') || !safeEqual(auth.slice(7).trim(), context.CONFIRM_TOKEN)) {
    return reply(401, { error: 'not_authorized' });
  }
  if (!cal.calendarConfigured(context) || !ai.aiConfigured(context)) return reply(503, { error: 'not_configured' });

  const { tz } = cal.config(context);
  if (!ai.withinCallingHours(context, tz)) return reply(422, { error: 'outside_calling_hours' });

  const dryRun = String(event.dry_run || '') === 'true';
  const dnc = ai.dncSet(context);
  const summary = { checked: 0, called: 0, skipped: 0, failed: 0, dry_run: dryRun };

  try {
    const items = await cal.listBookings(context, cal.tomorrowRange(context));
    const client = dryRun ? null : cal.twilioClient(context);
    for (const ev of items) {
      summary.checked++;
      const p = cal.eventProps(ev);
      if (p.pl_status !== 'booked' || p.pl_confirm_ok !== '1' || !p.pl_phone || dnc.has(p.pl_phone)) {
        summary.skipped++;
        continue;
      }
      if (dryRun) { summary.called++; continue; }
      const qs = new URLSearchParams({
        mode: 'confirm', event_id: ev.id,
        first_name: String(p.pl_name || '').split(' ')[0].replace(/[^A-Za-z' -]/g, '').slice(0, 40),
        vertical: p.pl_vertical || 'general',
        appointment_time: cal.label(new Date(ev.start.dateTime), tz),
      });
      try {
        await client.calls.create({
          to: p.pl_phone, from: context.CALLER_ID,
          url: `https://${context.DOMAIN_NAME}/ai-connect?${qs.toString()}`, method: 'POST',
          machineDetection: 'Enable', timeout: 30, timeLimit: parseInt(context.AI_MAX_CALL_SECONDS || '900', 10),
        });
        summary.called++;
      } catch (err) {
        summary.failed++;
        console.log(`CONFIRM_CALL_FAIL code=${err && err.code}`);
      }
    }
    console.log(`CONFIRM_RUN ${JSON.stringify(summary)}`);
    return reply(200, summary);
  } catch (err) {
    console.log(`CONFIRM_RUN_FAIL err=${err && err.message}`);
    return reply(502, { error: 'calendar_error' });
  }
};
