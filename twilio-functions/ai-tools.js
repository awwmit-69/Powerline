// PUBLIC function /ai-tools — server tools Maya (ElevenLabs agent) calls during a call.
// Auth: header `Authorization: Bearer <AI_TOOLS_TOKEN>` (set as a secret header in
// each ElevenLabs webhook tool). Action comes from ?action= or the JSON body.
//
// Actions:
//   availability  { from_date? YYYY-MM-DD }                        -> { slots: [{start,label}] }
//   book          { start, caller_name, callback_number, address_or_zip, vertical, notes, confirm_ok }
//   lookup        { callback_number }                             -> upcoming bookings for that phone
//   confirm       { event_id }
//   reschedule    { event_id, start }
//   cancel        { event_id, reason? }
//   message       { caller_name, callback_number, message }       -> owner gets a call/text
//
// Every write re-checks the calendar first, so two callers can never get the same slot.

const crypto = require('crypto');

function safeEqual(a, b) {
  const x = Buffer.from(String(a || ''));
  const y = Buffer.from(String(b || ''));
  return x.length > 0 && x.length === y.length && crypto.timingSafeEqual(x, y);
}

const clean = (v, max = 200) => String(v == null ? '' : v).replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max);
const truthy = (v) => ['true', 'yes', '1', 'on', 'y'].includes(String(v || '').trim().toLowerCase());

exports.handler = async function (context, event, callback) {
  const cal = require(Runtime.getFunctions()['calendar'].path);
  const { checkDestination } = require(Runtime.getFunctions()['dialrules'].path);
  const reply = (status, body) => {
    const r = new Twilio.Response();
    r.setStatusCode(status);
    r.appendHeader('Content-Type', 'application/json');
    r.appendHeader('Cache-Control', 'no-store');
    r.setBody(body);
    return callback(null, r);
  };

  const headers = (event.request && event.request.headers) || {};
  const auth = String(headers.authorization || '');
  if (!context.AI_TOOLS_TOKEN || !auth.startsWith('Bearer ') || !safeEqual(auth.slice(7).trim(), context.AI_TOOLS_TOKEN)) {
    return reply(401, { error: 'not_authorized' });
  }
  if (!cal.calendarConfigured(context)) {
    return reply(503, { error: 'booking_not_configured', say: 'Booking is offline right now. Take a message instead.' });
  }

  const action = clean(event.action, 20).toLowerCase();
  const { tz } = cal.config(context);
  const phoneOf = (raw) => {
    const d = checkDestination(raw, null);
    return d.ok ? d.e164 : '';
  };
  const owned = async (eventId) => {
    const ev = await cal.getEvent(context, clean(eventId, 200));
    const p = cal.eventProps(ev);
    return p.pl_booked === '1' && p.pl_status !== 'cancelled' && ev.status !== 'cancelled' ? ev : null;
  };

  try {
    if (action === 'availability') {
      const slots = await cal.availability(context, { fromDate: clean(event.from_date, 10), limit: 6 });
      if (!slots.length) return reply(200, { slots: [], say: 'No open times in the next two weeks. Take a message for a callback.' });
      return reply(200, { timezone: tz, slots: slots.map(({ start, label }) => ({ start, label })) });
    }

    if (action === 'book') {
      const slot = await cal.slotIsOpen(context, clean(event.start, 40));
      if (!slot) {
        const alt = await cal.availability(context, { limit: 3 });
        return reply(409, { error: 'slot_taken', say: 'That time just got taken. Offer one of these instead.', slots: alt.map(({ start, label }) => ({ start, label })) });
      }
      const phone = phoneOf(event.callback_number);
      if (!phone) return reply(422, { error: 'bad_phone', say: 'Ask for a valid 10-digit US phone number.' });
      const lead = {
        name: clean(event.caller_name, 80), phone, address: clean(event.address_or_zip, 160),
        vertical: clean(event.vertical, 20).toLowerCase(), notes: clean(event.notes, 500), confirmOk: truthy(event.confirm_ok),
      };
      const ev = await cal.createBooking(context, slot, lead);
      await cal.notifyOwner(context, `New appointment. ${lead.name || 'A caller'}, ${slot.label}. ${lead.vertical || ''} at ${lead.address || 'address not given'}. Callback ${phone.slice(2).split('').join(' ')}.`);
      console.log(`AI_BOOK ok event=${ev.id} slot=${slot.start}`);
      return reply(200, { ok: true, event_id: ev.id, label: slot.label });
    }

    if (action === 'lookup') {
      const phone = phoneOf(event.callback_number);
      if (!phone) return reply(422, { error: 'bad_phone' });
      const items = await cal.listBookings(context, { phone });
      return reply(200, {
        bookings: items.slice(0, 5).map((e) => ({
          event_id: e.id, label: cal.label(new Date(e.start.dateTime), tz), status: cal.eventProps(e).pl_status,
        })),
      });
    }

    if (action === 'confirm') {
      const ev = await owned(event.event_id);
      if (!ev) return reply(404, { error: 'not_found' });
      await cal.patchEvent(context, ev.id, {
        summary: ev.summary.startsWith('CONFIRMED') ? ev.summary : `CONFIRMED ${ev.summary}`,
        extendedProperties: { private: { ...cal.eventProps(ev), pl_status: 'confirmed' } },
      });
      return reply(200, { ok: true });
    }

    if (action === 'reschedule') {
      const ev = await owned(event.event_id);
      if (!ev) return reply(404, { error: 'not_found' });
      const slot = await cal.slotIsOpen(context, clean(event.start, 40));
      if (!slot) {
        const alt = await cal.availability(context, { limit: 3 });
        return reply(409, { error: 'slot_taken', slots: alt.map(({ start, label }) => ({ start, label })) });
      }
      const p = cal.eventProps(ev);
      await cal.patchEvent(context, ev.id, {
        start: { dateTime: slot.start }, end: { dateTime: slot.end },
        summary: ev.summary.replace(/^CONFIRMED /, ''),
        extendedProperties: { private: { ...p, pl_status: 'booked' } },
      });
      await cal.notifyOwner(context, `Rescheduled. ${p.pl_name || 'A customer'} moved to ${slot.label}.`);
      return reply(200, { ok: true, label: slot.label });
    }

    if (action === 'cancel') {
      const ev = await owned(event.event_id);
      if (!ev) return reply(404, { error: 'not_found' });
      const p = cal.eventProps(ev);
      await cal.patchEvent(context, ev.id, {
        summary: `CANCELLED ${ev.summary.replace(/^CONFIRMED /, '')}`,
        transparency: 'transparent', // frees the slot for freeBusy
        description: `${ev.description || ''}\nCancelled by caller: ${clean(event.reason, 200) || 'no reason given'}`,
        extendedProperties: { private: { ...p, pl_status: 'cancelled' } },
      });
      await cal.notifyOwner(context, `Cancelled. ${p.pl_name || 'A customer'} cancelled ${cal.label(new Date(ev.start.dateTime), tz)}.`);
      return reply(200, { ok: true });
    }

    if (action === 'message') {
      const phone = phoneOf(event.callback_number) || clean(event.callback_number, 20);
      const msg = clean(event.message, 300);
      await cal.notifyOwner(context, `Message from ${clean(event.caller_name, 80) || 'a caller'}, callback ${phone.replace(/^\+1/, '').split('').join(' ')}. ${msg}`);
      console.log('AI_MESSAGE ok');
      return reply(200, { ok: true });
    }

    return reply(400, { error: 'unknown_action' });
  } catch (err) {
    console.log(`AI_TOOLS_FAIL action=${action} err=${err && err.message}`);
    return reply(502, { error: 'calendar_error', say: 'The calendar is not responding. Take their details and tell them the team will call back to lock in a time.' });
  }
};
