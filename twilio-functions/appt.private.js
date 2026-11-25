// Appointment helpers (deploy as PRIVATE function at path /appt).
// Bookings live in a Twilio Sync Map (one item per booked slot), so the item
// key IS the slot: creating an item that already exists fails atomically,
// which makes double-booking impossible even if two calls race.
//
// Env (all optional):
//   APPT_DAYS=1,2,3,4,5,6        ISO weekdays (1=Mon … 7=Sun)   default Mon–Sat
//   APPT_START_HOUR=9  APPT_END_HOUR=18                         local to the homeowner
//   APPT_SLOT_MINUTES=60  APPT_HORIZON_DAYS=14  APPT_MIN_LEAD_MINUTES=120
//   APPT_TZ=America/New_York     fallback time zone
//   SYNC_SERVICE_SID=default  APPT_MAP=appointments

const WEEKDAYS = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

function config(context) {
  const n = (v, d) => {
    const x = parseInt(v, 10);
    return Number.isFinite(x) ? x : d;
  };
  return {
    days: String(context.APPT_DAYS || '1,2,3,4,5,6')
      .split(',')
      .map((s) => parseInt(s, 10))
      .filter((d) => d >= 1 && d <= 7),
    startHour: n(context.APPT_START_HOUR, 9),
    endHour: n(context.APPT_END_HOUR, 18),
    slotMinutes: n(context.APPT_SLOT_MINUTES, 60),
    horizonDays: n(context.APPT_HORIZON_DAYS, 14),
    minLeadMinutes: n(context.APPT_MIN_LEAD_MINUTES, 120),
    tz: context.APPT_TZ || 'America/New_York',
    syncService: context.SYNC_SERVICE_SID || 'default',
    mapName: context.APPT_MAP || 'appointments',
  };
}

function validTz(tz) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz }).format(new Date());
    return true;
  } catch (_) {
    return false;
  }
}

function zoneParts(ts, tz) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    weekday: 'short',
  }).formatToParts(new Date(ts));
  const get = (t) => parts.find((p) => p.type === t).value;
  return {
    y: +get('year'),
    m: +get('month'),
    d: +get('day'),
    h: +get('hour') % 24,
    min: +get('minute'),
    wd: WEEKDAYS[get('weekday')],
  };
}

// Local wall-clock time in tz -> UTC epoch ms (DST-safe via two-pass offset).
function zonedToUtc(y, m, d, h, min, tz) {
  const guess = Date.UTC(y, m - 1, d, h, min);
  const off1 = offsetMs(guess, tz);
  let ts = guess - off1;
  const off2 = offsetMs(ts, tz);
  if (off2 !== off1) ts = guess - off2;
  return ts;
}

function offsetMs(ts, tz) {
  const p = zoneParts(ts, tz);
  return Date.UTC(p.y, p.m - 1, p.d, p.h, p.min) - Math.floor(ts / 60000) * 60000;
}

function label(ts, tz) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short',
  }).format(new Date(ts));
}

const slotKey = (ts) => `slot-${new Date(ts).toISOString().slice(0, 16)}`; // slot-2026-11-24T15:00

// All bookable slot start times (UTC ms) in the window, in the homeowner's tz.
function allSlots(cfg, tz, now = Date.now()) {
  const earliest = now + cfg.minLeadMinutes * 60000;
  const out = [];
  const start = zoneParts(now, tz);
  for (let i = 0; i <= cfg.horizonDays; i++) {
    const day = new Date(Date.UTC(start.y, start.m - 1, start.d + i, 12));
    const y = day.getUTCFullYear();
    const m = day.getUTCMonth() + 1;
    const d = day.getUTCDate();
    const wd = zoneParts(zonedToUtc(y, m, d, 12, 0, tz), tz).wd;
    if (!cfg.days.includes(wd)) continue;
    for (let mins = cfg.startHour * 60; mins + cfg.slotMinutes <= cfg.endHour * 60; mins += cfg.slotMinutes) {
      const ts = zonedToUtc(y, m, d, Math.floor(mins / 60), mins % 60, tz);
      if (ts >= earliest) out.push(ts);
    }
  }
  return out;
}

// ---------- Sync storage ----------
function syncClient(context) {
  return require('twilio')(context.TWILIO_API_KEY_SID, context.TWILIO_API_KEY_SECRET, {
    accountSid: context.TWILIO_ACCOUNT_SID,
  });
}

async function mapHandle(context) {
  const cfg = config(context);
  const svc = syncClient(context).sync.v1.services(cfg.syncService);
  try {
    await svc.syncMaps(cfg.mapName).fetch();
  } catch (err) {
    if (err && err.status === 404) {
      try {
        await svc.syncMaps.create({ uniqueName: cfg.mapName });
      } catch (e2) {
        if (!(e2 && e2.code === 54301)) throw e2; // 54301 = already exists (race)
      }
    } else {
      throw err;
    }
  }
  return svc.syncMaps(cfg.mapName);
}

async function listBookings(context) {
  const map = await mapHandle(context);
  const items = await map.syncMapItems.list({ limit: 1000 });
  return items
    .filter((i) => i.key.startsWith('slot-'))
    .map((i) => ({ key: i.key, ...i.data }))
    .sort((a, b) => String(a.start).localeCompare(String(b.start)));
}

// Returns { ok:true, booking } or { ok:false, reason }.
async function createBooking(context, data) {
  const map = await mapHandle(context);
  const key = slotKey(Date.parse(data.start));
  try {
    await map.syncMapItems.create({ key, data });
    return { ok: true, booking: { key, ...data } };
  } catch (err) {
    if (err && (err.code === 54208 || err.status === 409)) return { ok: false, reason: 'slot_taken' };
    throw err;
  }
}

async function deleteBooking(context, key) {
  const map = await mapHandle(context);
  await map.syncMapItems(key).remove();
}

// ---------- ElevenLabs tool-call authentication ----------
// The agent's webhook tools send {{system__conversation_id}}. We confirm with
// ElevenLabs (using our own API key) that this conversation exists, belongs to
// our agent, and is live. No shared secret needed.
async function verifyConversation(context, conversationId, fetchImpl) {
  const id = String(conversationId || '');
  if (!/^conv_[A-Za-z0-9]{10,64}$/.test(id) || !context.ELEVENLABS_API_KEY) return false;
  try {
    const res = await (fetchImpl || fetch)(`https://api.elevenlabs.io/v1/convai/conversations/${id}`, {
      headers: { 'xi-api-key': context.ELEVENLABS_API_KEY },
    });
    if (!res.ok) return false;
    const conv = await res.json();
    if (conv.agent_id !== context.ELEVENLABS_AGENT_ID) return false;
    return ['initiated', 'in-progress', 'processing'].includes(conv.status);
  } catch (_) {
    return false;
  }
}

function toolResponse(status, body) {
  const response = new Twilio.Response();
  response.setStatusCode(status);
  response.appendHeader('Content-Type', 'application/json');
  response.setBody(body);
  return response;
}

module.exports = {
  config,
  validTz,
  zoneParts,
  zonedToUtc,
  label,
  slotKey,
  allSlots,
  listBookings,
  createBooking,
  deleteBooking,
  verifyConversation,
  toolResponse,
};
