// Shared dialing rules (deploy as PRIVATE function at path /dialrules).
// Used by /voice-outbound (browser agents) and /sip-outbound (softphones).
// US/Canada NANP only. Blocks emergency/N11, premium, and NANP codes billed
// at international rates (Caribbean, territories) to limit toll fraud.

const BLOCKED_NPA = new Set([
  '900', '500', '521', '522', '523', '524', '525', '526', '527', '528', '529',
  '533', '544', '566', '577', '588', '700', '710',
  '242', '246', '264', '268', '284', '340', '345', '441', '473', '649', '658',
  '664', '670', '671', '684', '721', '758', '767', '784', '787', '809', '829',
  '849', '868', '869', '876', '939',
]);

const EMERGENCY_OR_SHORT = /^\+?1?(911|933|112|999|[2-9]11)$/;

function cleanDigits(raw) {
  let s = String(raw || '');
  try {
    s = decodeURIComponent(s);
  } catch (_) {
    // keep raw
  }
  return s.replace(/[\s\-().]/g, '');
}

function normalizeNanp(raw) {
  const d = cleanDigits(raw);
  if (/^\+1\d{10}$/.test(d)) return d;
  if (/^1\d{10}$/.test(d)) return `+${d}`;
  if (/^\d{10}$/.test(d)) return `+1${d}`;
  return null;
}

// Returns { ok: true, e164 } or { ok: false, reason, message }.
function checkDestination(raw, callerId) {
  const digits = cleanDigits(raw);
  if (EMERGENCY_OR_SHORT.test(digits) || digits.replace(/\D/g, '').length < 10) {
    return {
      ok: false,
      reason: 'emergency_or_short',
      message:
        'Emergency and short code calls are not supported on this line. Please hang up and dial from a mobile phone or landline.',
    };
  }
  const e164 = normalizeNanp(digits);
  if (!e164 || !/^\+1[2-9]\d{2}[2-9]\d{6}$/.test(e164)) {
    return {
      ok: false,
      reason: 'invalid_destination',
      message:
        'Only United States and Canada numbers can be dialed from this line. Please dial ten digits.',
    };
  }
  const npa = e164.slice(2, 5);
  if (BLOCKED_NPA.has(npa) || e164.slice(5, 8) === '976') {
    return { ok: false, reason: `blocked_npa:${npa}`, message: 'That destination is blocked on this line.' };
  }
  if (callerId && e164 === callerId) {
    return { ok: false, reason: 'self_dial', message: 'You cannot call this line from itself.' };
  }
  return { ok: true, e164 };
}

// AGENTS env format: "agentId:+15551234567,agent2:+15557654321"
function parseAgents(value) {
  const map = new Map();
  String(value || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .forEach((pair) => {
      const idx = pair.indexOf(':');
      if (idx <= 0) return;
      const id = pair.slice(0, idx).trim().toLowerCase();
      const phone = pair.slice(idx + 1).trim();
      if (/^[a-z0-9_.-]{2,32}$/.test(id) && /^\+[1-9]\d{7,14}$/.test(phone)) map.set(id, phone);
    });
  return map;
}

function rejectTwiml(twiml, message) {
  twiml.say({ voice: 'Polly.Joanna' }, message);
  twiml.hangup();
  return twiml;
}

module.exports = { checkDestination, normalizeNanp, parseAgents, rejectTwiml, BLOCKED_NPA };
