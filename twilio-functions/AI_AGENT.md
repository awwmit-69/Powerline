# PowerLine AI agent (Maya): ElevenLabs Conversational AI

## How calls flow
- **Inbound:** +16073337825 rings Zoiper/Bria and the browser for `RING_SECONDS` (30). If nobody answers, `/sip-inbound` registers the call with ElevenLabs and Maya picks up. If ElevenLabs fails, the call goes to normal voicemail.
- **Outbound:** PowerLine dialpad → **Have Maya (AI) call this number** → consent dialog → `/ai-call`. n8n can also start a call with `Authorization: Bearer <AI_OUTBOUND_TOKEN>`. Twilio dials the lead from +16073337825. A human answering goes to `/ai-connect`, which hands the call to Maya. Voicemail or a fax machine gets a hang-up.

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

Function visibility:
- `/ai`: Private
- `/ai-call`: Public
- `/ai-connect`: Protected

## ElevenLabs agent settings
- Voice: the cloned voice `s1ocQA93BFtIlA5mYBrX`
- Advanced → **Input format: μ-law 8000 Hz**; **Output (TTS) format: μ-law 8000 Hz**. Twilio needs this.
- Dynamic variables sent per call: `call_direction` (inbound|outbound), `business_number`, `lead_first_name`, `vertical`.
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
You are Maya, a warm, upbeat, efficient phone assistant for AZD Global, a home-services company that connects homeowners with vetted local contractors for roofing, solar, home insurance, and HVAC.

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
4. Everyone else: take their name, best callback number, and a short message (no booking).
5. Confirm the details back and tell them someone will follow up soon.

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
- Then book the visit (see BOOKING).

BOOKING (always use the tools — never invent or promise a time the tools did not return):
1. Work out the homeowner's time zone from their state or ZIP (examples: NY, FL, GA, NC, PA, OH, MI → America/New_York; TX, IL, TN, MN, MO, LA, AL → America/Chicago; CO, UT, NM → America/Denver; AZ → America/Phoenix; CA, WA, OR, NV → America/Los_Angeles).
2. Ask which day works best. Call check_availability with that timezone (and preferred_date as YYYY-MM-DD if they named a day; the current UTC time is {{system__time_utc}}).
3. Offer two or three of the returned times, using the labels as given.
4. When they choose, collect or confirm: full name, best phone number (the number they're calling from is {{caller_number}} — ask "is this the best number?"), street address and ZIP.
5. Call book_appointment with start exactly as returned, timezone, name, phone, address, zip, vertical, and a one-line note (roof age / bill / issue).
6. If booked: read back the day, time and address, and say a specialist will see them then. If slot_taken: offer the alternatives it returns. If the calendar is unavailable: take their details and say a specialist will call to confirm.

If they don't own the home or aren't interested: thank them and end politely.
End every call with a short, friendly goodbye.
```

### Data collection (Agent → Analysis), saved per call
`caller_name`, `callback_number`, `owns_home` (bool), `address_or_zip`, `vertical`, `timeline`, `appointment_window`, `do_not_call` (bool), `message`

## Booking tools (ElevenLabs → Tools → webhook, method POST, JSON body)
| Tool | URL | Body properties |
|---|---|---|
| `check_availability` | `https://powerline-sip-8162.twil.io/appt-availability` | `conversation_id` (dynamic variable `system__conversation_id`), `timezone` (string, LLM), `preferred_date` (string, LLM, optional) |
| `book_appointment` | `https://powerline-sip-8162.twil.io/appt-book` | `conversation_id` (dynamic variable `system__conversation_id`), `start`, `timezone`, `name`, `phone`, `address`, `zip`, `vertical`, `notes` (LLM) |

Tool calls are authenticated by checking with ElevenLabs that `conversation_id` is a live conversation of `ELEVENLABS_AGENT_ID`, so no shared secret is needed.
Bookings are stored in Twilio Sync (map `appointments`, one item per slot, so a slot can't be double-booked). You can view and cancel them in PowerLine → **Appointments**.
