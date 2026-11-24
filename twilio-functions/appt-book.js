// PUBLIC function /appt-book — Maya's "book_appointment" webhook tool.
// POST JSON: { conversation_id, start (ISO from check_availability), timezone,
//              name, phone, address, zip, vertical, notes }
// One booking per slot (Sync item key = slot). Taken -> returns alternatives.

const VERTICALS = new Set(['roofing', 'solar', 'insurance', 'hvac', 'general']);
const clip = (v, n) => String(v || '').replace(/\s+/g, ' ').trim().slice(0, n);

exports.handler = async function (context, event, callback) {
  const appt = require(Runtime.getFunctions()['appt'].path);
  const { normalizeNanp } = require(Runtime.getFunctions()['dialrules'].path);
  const cfg = appt.config(context);

  if (!(await appt.verifyConversation(context, event.conversation_id))) {
    return callback(null, appt.toolResponse(401, { error: 'unauthorized' }));
  }

  const tz = appt.validTz(event.timezone) ? event.timezone : cfg.tz;
  const startTs = Date.parse(String(event.start || ''));
  const name = clip(event.name, 80);
  const phone = normalizeNanp(event.phone);
  const address = clip(event.address, 160);
  const zip = clip(event.zip, 10);

  const missing = [];
  if (!name) missing.push('name');
  if (!phone) missing.push('phone');
  if (!address && !zip) missing.push('address or ZIP');
  if (!Number.isFinite(startTs)) missing.push('start');
  if (missing.length) {
    return callback(null, appt.toolResponse(200, { booked: false, error: 'missing_fields', message: `Ask the caller for: ${missing.join(', ')}.` }));
  }

  const valid = new Set(appt.allSlots(cfg, tz).map((ts) => appt.slotKey(ts)));
  if (!valid.has(appt.slotKey(startTs))) {
    return callback(null, appt.toolResponse(200, { booked: false, error: 'invalid_time', message: 'That time is not bookable. Call check_availability and offer one of those times.' }));
  }

  const vertical = VERTICALS.has(String(event.vertical || '').toLowerCase()) ? String(event.vertical).toLowerCase() : 'general';
  const data = {
    start: new Date(startTs).toISOString(),
    minutes: cfg.slotMinutes,
    timezone: tz,
    name,
    phone,
    address,
    zip,
    vertical,
    notes: clip(event.notes, 500),
    conversation_id: String(event.conversation_id),
    created_at: new Date().toISOString(),
    source: 'maya',
  };

  try {
    const result = await appt.createBooking(context, data);
    if (!result.ok) {
      const taken = new Set((await appt.listBookings(context)).map((b) => b.key));
      const alts = appt.allSlots(cfg, tz).filter((ts) => !taken.has(appt.slotKey(ts))).slice(0, 3);
      console.log(`APPT_TAKEN slot=${appt.slotKey(startTs)}`);
      return callback(
        null,
        appt.toolResponse(200, {
          booked: false,
          error: 'slot_taken',
          message: `That time was just taken. Offer: ${alts.map((ts) => appt.label(ts, tz)).join('; ')}.`,
          alternatives: alts.map((ts) => ({ start: new Date(ts).toISOString(), label: appt.label(ts, tz) })),
        }),
      );
    }
    console.log(`APPT_BOOKED slot=${result.booking.key} vertical=${vertical} npa=${phone.slice(2, 5)}`);
    return callback(
      null,
      appt.toolResponse(200, {
        booked: true,
        confirmation: result.booking.key,
        label: appt.label(startTs, tz),
        message: `Booked for ${appt.label(startTs, tz)}. Confirm the time and address back to the caller.`,
      }),
    );
  } catch (err) {
    console.log(`APPT_BOOK_FAIL code=${err && err.code}`);
    return callback(null, appt.toolResponse(500, { booked: false, error: 'calendar_unavailable', message: 'Take their details and preferred time; a specialist will confirm.' }));
  }
};
