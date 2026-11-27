// Booking helpers (deploy as PRIVATE function at path /calendar).
// Google Calendar via a service account: the business owner shares their
// calendar with GOOGLE_SA_EMAIL ("Make changes to events"). No attendees are
// added (plain service accounts cannot invite), so the owner is told about new
// bookings by a short Twilio phone call and/or SMS (notifyOwner).
//
// Env: GOOGLE_SA_EMAIL, GOOGLE_SA_KEY (secret, PEM; literal \n allowed),
//      BOOKING_CALENDAR_ID (e.g. owner@gmail.com), BOOKING_TZ (America/New_York),
//      BOOKING_DAYS (1-6 = Mon-Sat, 0 = Sun), BOOKING_HOURS (9-18 = last start 17:00),
//      BOOKING_SLOT_MINUTES (60), BOOKING_LEAD_MINUTES (120), BOOKING_HORIZON_DAYS (14),
//      BUSINESS_NAME, OWNER_NOTIFY_PHONE (E.164), OWNER_NOTIFY_SMS (on|off, needs A2P/TF verification).

const crypto = require('crypto');

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const CAL = 'https://www.googleapis.com/calendar/v3';

// ---------------- time zone math (no dependencies) ----------------
function wallParts(date, tz) {
  const parts = {};
  for (const p of new Intl.DateTimeFormat('en-US', {
    timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  }).formatToParts(date)) parts[p.type] = p.value;
  return { y: +parts.year, mo: +parts.month, d: +parts.day, h: +parts.hour % 24, mi: +parts.minute, s: +parts.second };
}

function offsetMs(date, tz) {
  const p = wallParts(date, tz);
  return Date.UTC(p.y, p.mo - 1, p.d, p.h, p.mi, p.s) - Math.floor(date.getTime() / 1000) * 1000;
}

// Wall-clock time in tz -> real instant (handles DST).
function zonedToUtc(y, mo, d, h, mi, tz) {
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  const off1 = offsetMs(new Date(guess), tz);
  let t = guess - off1;
  const off2 = offsetMs(new Date(t), tz);
  if (off2 !== off1) t = guess - off2;
  return new Date(t);
}

function parseDays(spec) {
  const out = new Set();
  for (const part of String(spec || '1-6').split(',')) {
    const [a, b] = part.split('-').map((n) => parseInt(n, 10));
    if (Number.isNaN(a)) continue;
    const last = Number.isFinite(b) ? b : a;
    for (let i = a; i <= last; i++) out.add(((i % 7) + 7) % 7);
  }
  return out;
}

function config(context) {
  const [startH, endH] = String(context.BOOKING_HOURS || '9-18').split('-').map((n) => parseInt(n, 10));
  return {
    tz: context.BOOKING_TZ || 'America/New_York',
    days: parseDays(context.BOOKING_DAYS || '1-6'),
    startH: Number.isNaN(startH) ? 9 : startH,
    endH: Number.isNaN(endH) ? 18 : endH,
    slot: parseInt(context.BOOKING_SLOT_MINUTES || '60', 10),
    lead: parseInt(context.BOOKING_LEAD_MINUTES || '120', 10),
    horizon: parseInt(context.BOOKING_HORIZON_DAYS || '14', 10),
  };
}

function label(date, tz) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: tz, weekday: 'long', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit',
  }).format(date);
}

const overlaps = (aStart, aEnd, b) => aStart < new Date(b.end) && aEnd > new Date(b.start);

// Pure: open slots from `now`, skipping busy intervals. `fromDate` (YYYY-MM-DD,
// in tz) starts the search on that day. One appointment per slot.
function openSlots(context, { now = new Date(), busy = [], limit = 6, fromDate } = {}) {
  const c = config(context);
  const earliest = new Date(now.getTime() + c.lead * 60000);
  let base = wallParts(now, c.tz);
  if (fromDate && /^\d{4}-\d{2}-\d{2}$/.test(fromDate)) {
    const [y, mo, d] = fromDate.split('-').map(Number);
    if (Date.UTC(y, mo - 1, d) > Date.UTC(base.y, base.mo - 1, base.d)) base = { y, mo, d };
  }
  const out = [];
  for (let i = 0; i <= c.horizon && out.length < limit; i++) {
    const day = new Date(Date.UTC(base.y, base.mo - 1, base.d + i));
    if (!c.days.has(day.getUTCDay())) continue;
    for (let h = c.startH; h * 60 + c.slot <= c.endH * 60 && out.length < limit; h++) {
      const start = zonedToUtc(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate(), h, 0, c.tz);
      const end = new Date(start.getTime() + c.slot * 60000);
      if (start < earliest) continue;
      if (busy.some((b) => overlaps(start, end, b))) continue;
      out.push({ start: start.toISOString(), end: end.toISOString(), label: label(start, c.tz) });
    }
  }
  return out;
}

// ---------------- Google auth + Calendar API ----------------
let cachedToken = null;

const b64url = (s) => Buffer.from(s).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

function calendarConfigured(context) {
  return Boolean(context.GOOGLE_SA_EMAIL && context.GOOGLE_SA_KEY && context.BOOKING_CALENDAR_ID);
}

async function accessToken(context, doFetch) {
  if (cachedToken && cachedToken.exp > Date.now() + 60000 && cachedToken.email === context.GOOGLE_SA_EMAIL) {
    return cachedToken.value;
  }
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: context.GOOGLE_SA_EMAIL, scope: 'https://www.googleapis.com/auth/calendar',
    aud: TOKEN_URL, iat: now, exp: now + 3600,
  }));
  const key = String(context.GOOGLE_SA_KEY).replace(/\\n/g, '\n');
  const sig = crypto.createSign('RSA-SHA256').update(`${head}.${claims}`).sign(key)
    .toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
  const res = await doFetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${head}.${claims}.${sig}` }).toString(),
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) throw new Error(`google_auth_failed status=${res.status}`);
  cachedToken = { value: json.access_token, exp: Date.now() + (json.expires_in || 3600) * 1000, email: context.GOOGLE_SA_EMAIL };
  return cachedToken.value;
}

async function gcal(context, method, path, body, fetchImpl) {
  const doFetch = fetchImpl || fetch;
  const token = await accessToken(context, doFetch);
  const res = await doFetch(`${CAL}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = res.status === 204 ? {} : await res.json();
  if (!res.ok) throw new Error(`gcal_${method}_failed status=${res.status}`);
  return json;
}

const calPath = (context) => `/calendars/${encodeURIComponent(context.BOOKING_CALENDAR_ID)}`;

async function busyTimes(context, timeMin, timeMax, fetchImpl) {
  const json = await gcal(context, 'POST', '/freeBusy', {
    timeMin, timeMax, items: [{ id: context.BOOKING_CALENDAR_ID }],
  }, fetchImpl);
  const cal = (json.calendars || {})[context.BOOKING_CALENDAR_ID] || {};
  if (cal.errors && cal.errors.length) throw new Error('calendar_not_shared');
  return cal.busy || [];
}

// Live availability: freeBusy over the horizon, then openSlots.
async function availability(context, { fromDate, limit = 6, now = new Date() } = {}, fetchImpl) {
  const c = config(context);
  const timeMax = new Date(now.getTime() + (c.horizon + 1) * 86400000).toISOString();
  const busy = await busyTimes(context, now.toISOString(), timeMax, fetchImpl);
  return openSlots(context, { now, busy, limit, fromDate });
}

// True when `startIso` is a currently open slot (re-checked right before writing).
async function slotIsOpen(context, startIso, fetchImpl, now = new Date()) {
  const slots = await availability(context, { limit: 500, now }, fetchImpl);
  const t = Date.parse(startIso);
  return slots.find((s) => Date.parse(s.start) === t) || null;
}

function eventProps(e) {
  return ((e && e.extendedProperties) || {}).private || {};
}

async function createBooking(context, slot, lead, fetchImpl) {
  const biz = context.BUSINESS_NAME || 'AZD Global';
  const lines = [
    `Booked by ${biz} AI assistant (PowerLine)`,
    `Name: ${lead.name || '-'}`,
    `Phone: ${lead.phone || '-'}`,
    `Address/ZIP: ${lead.address || '-'}`,
    `Service: ${lead.vertical || '-'}`,
    `Notes: ${lead.notes || '-'}`,
    `OK to call/text to confirm: ${lead.confirmOk ? 'yes' : 'no'}`,
  ];
  return gcal(context, 'POST', `${calPath(context)}/events`, {
    summary: `${lead.vertical ? lead.vertical[0].toUpperCase() + lead.vertical.slice(1) : 'Appointment'}: ${lead.name || 'New lead'}`,
    description: lines.join('\n'),
    location: lead.address || undefined,
    start: { dateTime: slot.start },
    end: { dateTime: slot.end },
    extendedProperties: {
      private: {
        pl_booked: '1', pl_status: 'booked', pl_phone: lead.phone || '', pl_name: lead.name || '',
        pl_confirm_ok: lead.confirmOk ? '1' : '0', pl_vertical: lead.vertical || '',
      },
    },
  }, fetchImpl);
}

async function getEvent(context, eventId, fetchImpl) {
  return gcal(context, 'GET', `${calPath(context)}/events/${encodeURIComponent(eventId)}`, null, fetchImpl);
}

async function patchEvent(context, eventId, patch, fetchImpl) {
  return gcal(context, 'PATCH', `${calPath(context)}/events/${encodeURIComponent(eventId)}`, patch, fetchImpl);
}

// Upcoming PowerLine bookings, optionally filtered by phone.
async function listBookings(context, { timeMin, timeMax, phone } = {}, fetchImpl) {
  const qs = new URLSearchParams({
    timeMin: timeMin || new Date().toISOString(), singleEvents: 'true', orderBy: 'startTime', maxResults: '250',
  });
  if (timeMax) qs.set('timeMax', timeMax);
  qs.append('privateExtendedProperty', 'pl_booked=1');
  if (phone) qs.append('privateExtendedProperty', `pl_phone=${phone}`);
  const json = await gcal(context, 'GET', `${calPath(context)}/events?${qs}`, null, fetchImpl);
  return (json.items || []).filter((e) => e.status !== 'cancelled' && eventProps(e).pl_status !== 'cancelled');
}

// Start/end (ISO) of "tomorrow" in the booking time zone.
function tomorrowRange(context, now = new Date()) {
  const { tz } = config(context);
  const p = wallParts(now, tz);
  const d = new Date(Date.UTC(p.y, p.mo - 1, p.d + 1));
  const start = zonedToUtc(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), 0, 0, tz);
  const e = new Date(Date.UTC(p.y, p.mo - 1, p.d + 2));
  const end = zonedToUtc(e.getUTCFullYear(), e.getUTCMonth() + 1, e.getUTCDate(), 0, 0, tz);
  return { timeMin: start.toISOString(), timeMax: end.toISOString() };
}

// ---------------- Twilio + owner notifications ----------------
function twilioClient(context) {
  if (context.__TEST_TWILIO) return context.__TEST_TWILIO;
  return require('twilio')(context.TWILIO_API_KEY_SID, context.TWILIO_API_KEY_SECRET, { accountSid: context.TWILIO_ACCOUNT_SID });
}

const xmlEscape = (s) => String(s).replace(/[<>&'"]/g, (ch) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[ch]));

// Tells the owner by voice call (works without A2P) and/or SMS. Never throws.
async function notifyOwner(context, text) {
  const to = String(context.OWNER_NOTIFY_PHONE || '').trim();
  if (!to || !context.CALLER_ID) return { called: false, texted: false };
  const client = twilioClient(context);
  const result = { called: false, texted: false };
  const say = xmlEscape(text);
  try {
    await client.calls.create({
      to, from: context.CALLER_ID, timeout: 25,
      twiml: `<Response><Say voice="Polly.Joanna">PowerLine alert. ${say}</Say><Pause length="1"/><Say voice="Polly.Joanna">Again. ${say}</Say></Response>`,
    });
    result.called = true;
  } catch (err) {
    console.log(`OWNER_NOTIFY_CALL_FAIL code=${err && err.code}`);
  }
  if (String(context.OWNER_NOTIFY_SMS || '').toLowerCase() === 'on') {
    try {
      await client.messages.create({ to, from: context.CALLER_ID, body: `PowerLine: ${text}`.slice(0, 600) });
      result.texted = true;
    } catch (err) {
      console.log(`OWNER_NOTIFY_SMS_FAIL code=${err && err.code}`);
    }
  }
  return result;
}

module.exports = {
  wallParts, zonedToUtc, parseDays, openSlots, label, config,
  calendarConfigured, availability, slotIsOpen, createBooking, getEvent, patchEvent,
  listBookings, tomorrowRange, eventProps, notifyOwner, twilioClient,
  _resetTokenCache: () => { cachedToken = null; },
};
