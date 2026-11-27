# PowerLine AI agent (Maya): ElevenLabs Conversational AI

## How calls flow
- **Inbound:** +16073337825 rings Zoiper/Bria and the browser for `RING_SECONDS` (30). If nobody answers, `/sip-inbound` registers the call with ElevenLabs and Maya picks up. If ElevenLabs fails, the call goes to normal voicemail.
- **Outbound:** PowerLine dialpad → **Have Maya (AI) call this number** → consent dialog → `/ai-call`. n8n can also start a call with `Authorization: Bearer <AI_OUTBOUND_TOKEN>`. Twilio dials the lead from +16073337825. A human answering goes to `/ai-connect`, which hands the call to Maya. Voicemail or a fax machine gets a hang-up.

- **Booking:** during a call Maya uses the `/ai-tools` server tools to read real open times from the owner's Google Calendar and book, look up, confirm, reschedule or cancel. The owner gets a short phone call (and a text once SMS is registered) for every booking, change and message.
- **Daily confirm/rebook:** `.github/workflows/daily-confirm.yml` runs every day at 10:23 AM ET and hits `/confirm-run`. Maya calls everyone booked for tomorrow who agreed to a confirmation call, and they confirm, reschedule or cancel.

`/ai-call` refuses a call when any of these is true:
- the consent source or date is missing
- the number is in `DNC_NUMBERS`
- it's outside 8am–9pm in the lead's time zone
- the destination is blocked (911/N11, premium-rate, Caribbean, self-dial)

## Twilio Functions: environment variables
| Variable | Value | Secret |
|---|---|---|
| `ELEVENLABS_API_KEY` | ElevenLabs API key. Needs Conversational AI / Agents access | **yes** (only the owner pastes it) |
| `ELEVENLABS_AGENT_ID` | `agent_…` from the ElevenLabs agent page | no |
| `AI_INBOUND` | `on` (default) / `off` | no |
| `AI_OUTBOUND` | `off` (default) / `on` | no |
| `AI_OUTBOUND_TOKEN` | random 32+ characters, only needed for n8n | yes |
| `AI_CALL_HOURS` | `8-21` | no |
| `AI_DEFAULT_TZ` | `America/New_York` | no |
| `AI_MAX_CALL_SECONDS` | `900` | no |
| `DNC_NUMBERS` | comma list of E.164 numbers | no |
| `BUSINESS_NAME` | name Maya says, e.g. `AZD Global` or the client's company | no |
| `AI_TOOLS_TOKEN` | random 32+ chars; the same value goes in each ElevenLabs tool header | yes |
| `CONFIRM_TOKEN` | random 32+ chars; also a GitHub repo secret | yes |
| `GOOGLE_SA_EMAIL` | service account email (`...@...iam.gserviceaccount.com`) | no |
| `GOOGLE_SA_KEY` | the service account's `private_key` (PEM; literal `\n` is fine) | **yes** |
| `BOOKING_CALENDAR_ID` | the owner's calendar ID, usually their Gmail address | no |
| `BOOKING_TZ` | `America/New_York` | no |
| `BOOKING_DAYS` | `1-6` (Mon–Sat; 0 = Sunday) | no |
| `BOOKING_HOURS` | `9-18` (first start 9:00, last start 17:00) | no |
| `BOOKING_SLOT_MINUTES` | `60` | no |
| `BOOKING_LEAD_MINUTES` | `120` (no bookings sooner than this) | no |
| `OWNER_NOTIFY_PHONE` | owner's cell in E.164; gets a call per booking/message | no |
| `OWNER_NOTIFY_SMS` | `off` until A2P 10DLC or toll-free verification is approved, then `on` | no |

Function visibility:
- `/ai`: Private
- `/ai-call`: Public
- `/ai-connect`: Protected
- `/calendar`: Private
- `/ai-tools`: Public (Bearer `AI_TOOLS_TOKEN`)
- `/confirm-run`: Public (Bearer `CONFIRM_TOKEN`)

## Google Calendar setup (one time per business)
1. Google Cloud console → new project → enable **Google Calendar API**.
2. IAM → Service accounts → create one → Keys → **Add key → JSON**. Its `client_email` goes in `GOOGLE_SA_EMAIL` and its `private_key` in `GOOGLE_SA_KEY`.
3. In the owner's Google Calendar: Settings → the calendar → **Share with specific people** → add the service account email with **Make changes to events**.
4. Set `BOOKING_CALENDAR_ID` to that calendar's ID (Settings → Integrate calendar → Calendar ID).

Maya only offers times that are free on that calendar, so the owner can block time just by adding events.

## ElevenLabs tools (Agent → Tools → Add tool → Webhook)
Every tool: method **POST**, header `Authorization: Bearer <AI_TOOLS_TOKEN>` (store as a secret), URL `https://<service>.twil.io/ai-tools?action=<name>`.

| Tool name | `action` | Body parameters (all strings) | Description to paste |
|---|---|---|---|
| `check_availability` | `availability` | `from_date` (optional, YYYY-MM-DD) | Get the next open appointment times. Always call before offering times. |
| `book_appointment` | `book` | `start` (exact ISO value from check_availability), `caller_name`, `callback_number`, `address_or_zip`, `vertical`, `notes`, `confirm_ok` (yes/no) | Book the chosen time. Only after the caller picks a slot and you confirmed their details. |
| `find_appointment` | `lookup` | `callback_number` | Find a caller's upcoming appointments. Use when they want to change or cancel. |
| `confirm_appointment` | `confirm` | `event_id` | Mark an appointment confirmed. |
| `reschedule_appointment` | `reschedule` | `event_id`, `start` | Move an appointment to a new open time. |
| `cancel_appointment` | `cancel` | `event_id`, `reason` | Cancel an appointment. |
| `take_message` | `message` | `caller_name`, `callback_number`, `message` | Pass a message to the owner right away. |

If a tool response contains `say`, follow it. If a booking returns `slot_taken`, offer the `slots` it returns.

## ElevenLabs agent settings
- Voice: the cloned voice `s1ocQA93BFtIlA5mYBrX`
- Advanced → **Input format: μ-law 8000 Hz**; **Output (TTS) format: μ-law 8000 Hz**. Twilio needs this.
- Dynamic variables sent per call: `call_direction` (inbound|outbound|confirm), `business_name`, `business_number`, `caller_number` (inbound), `lead_first_name`, `vertical`, `event_id` + `appointment_time` (confirm). PowerLine sends all of them on every call (`none` when not used), because ElevenLabs won't start a call when a variable used in the prompt is missing.
- First message: `{{call_direction}}`-aware. See the prompt below.

### First message
```
Hi, this is Maya, an AI assistant with AZD Global — this call may be recorded. How can I help you today?
```
Use this one for outbound calls (or rely on the prompt):
```
Hi {{lead_first_name}}, this is Maya, an AI assistant calling from AZD Global about the {{vertical}} quote you requested. Is now an okay time for a quick minute?
```

### System prompt
```
You are Maya, a warm, upbeat, efficient phone assistant for {{business_name}}, a home-services business (roofing, solar, home insurance, HVAC).

ALWAYS:
- Say you are an AI assistant in your first sentence. If asked whether you are a real person, say no, you are an AI assistant.
- Keep each turn to 1–2 short sentences. Sound natural, not scripted. Never talk over the caller.
- If the person says stop, remove me, do not call, or not interested: apologize, confirm they will not be called again, and end the call politely.
- Never promise prices, savings, approvals, or tax credits. Never ask for SSN, bank, or card details.
- Emergencies: tell them to hang up and dial 911. You cannot connect emergency calls.

CALL TYPE: {{call_direction}}

IF INBOUND (someone called us and no one picked up):
1. Greet, say the team is busy, and that you can help or take a message.
2. Find out why they're calling. Possible reasons:
   - a homeowner looking for a service
   - an existing customer
   - a contractor or partner
   - something else
3. Homeowner looking for a service: run the qualification below.
   - wants to change or cancel an appointment: call find_appointment with their number ({{caller_number}} unless they give another), then reschedule_appointment or cancel_appointment.
4. Everyone else: take their name, best callback number, and a short message, then call take_message.
5. Confirm the details back and tell them someone will follow up soon.

IF CONFIRM (we booked them for {{appointment_time}}; event {{event_id}}):
1. Greet {{lead_first_name}}, say you're the AI assistant from {{business_name}} calling to confirm tomorrow's appointment at {{appointment_time}}.
2. Yes → call confirm_appointment with event_id {{event_id}}, thank them, end.
3. Needs a new time → call check_availability, offer two options, then reschedule_appointment with event_id {{event_id}}.
4. No longer wants it → call cancel_appointment with event_id {{event_id}} and a short reason.

IF OUTBOUND (they requested a {{vertical}} quote and agreed to be contacted):
1. Greet {{lead_first_name}} by name and confirm it's a good time. If not, ask for a better time and end.
2. Run the qualification.

QUALIFICATION (one question at a time):
- Confirm they own the home (not renting) and the property address or ZIP code.
- {{vertical}} specifics:
  - roofing: roof age, leaks/storm damage, insurance claim filed?
  - solar: average monthly electric bill, roof shade, who the utility is
  - insurance: current carrier, renewal month, home age
  - hvac: system age, what's wrong (no heat/cool, noisy, high bills), repair or replace
- Timeline: within 30 days, 1–3 months, or just researching.
- All decision-makers available for a 30-minute visit?
- Offer an appointment: call check_availability, then offer two of the returned times by their label. Never invent a time.
- Confirm name, best number, and address. Ask: "Is it okay if we call this number the day before to confirm?" (that's confirm_ok).
- Call book_appointment with the exact `start` value of the slot they chose. Read back the day and time from the result.

If they don't own the home or aren't interested: thank them and end politely.
End every call with a short, friendly goodbye.
```

### Data collection (Agent → Analysis), saved per call
`caller_name`, `callback_number`, `owns_home` (bool), `address_or_zip`, `vertical`, `timeline`, `appointment_booked` (bool), `do_not_call` (bool), `message`
