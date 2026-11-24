// PUBLIC function /appt-availability — Maya's "check_availability" webhook tool.
// POST JSON: { conversation_id, timezone?, preferred_date? (YYYY-MM-DD, homeowner local) }
// Returns up to 6 open slots: [{ start (ISO UTC), label (spoken form) }].
// Auth: conversation_id must be a live conversation of our ElevenLabs agent.

exports.handler = async function (context, event, callback) {
  const appt = require(Runtime.getFunctions()['appt'].path);
  const cfg = appt.config(context);

  if (!(await appt.verifyConversation(context, event.conversation_id))) {
    return callback(null, appt.toolResponse(401, { error: 'unauthorized' }));
  }

  const tz = appt.validTz(event.timezone) ? event.timezone : cfg.tz;
  try {
    const taken = new Set((await appt.listBookings(context)).map((b) => b.key));
    let open = appt.allSlots(cfg, tz).filter((ts) => !taken.has(appt.slotKey(ts)));
    const pref = String(event.preferred_date || '').trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(pref)) {
      const onDay = open.filter((ts) => {
        const p = appt.zoneParts(ts, tz);
        return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}` === pref;
      });
      if (onDay.length) open = onDay;
    }
    const slots = open.slice(0, 6).map((ts) => ({ start: new Date(ts).toISOString(), label: appt.label(ts, tz) }));
    console.log(`APPT_AVAIL tz=${tz} pref=${pref || '-'} open=${slots.length}`);
    return callback(
      null,
      appt.toolResponse(200, {
        timezone: tz,
        slots,
        message: slots.length
          ? `Offer the caller two or three of these times: ${slots.slice(0, 3).map((s) => s.label).join('; ')}.`
          : 'No open times in the next two weeks. Take their details and say a specialist will call to schedule.',
      }),
    );
  } catch (err) {
    console.log(`APPT_AVAIL_FAIL code=${err && err.code}`);
    return callback(null, appt.toolResponse(500, { error: 'calendar_unavailable', message: 'Take their details; a specialist will call to schedule.' }));
  }
};
