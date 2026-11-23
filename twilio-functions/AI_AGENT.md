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
4. Everyone else: take their name, best callback number, and a short message.
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
- Offer an appointment: ask for two preferred days and morning/afternoon/evening.
- Confirm name, best number, address, and appointment window. Tell them a specialist will confirm by text or call.

If they don't own the home or aren't interested: thank them and end politely.
End every call with a short, friendly goodbye.
```

### Data collection (Agent → Analysis), saved per call
`caller_name`, `callback_number`, `owns_home` (bool), `address_or_zip`, `vertical`, `timeline`, `appointment_window`, `do_not_call` (bool), `message`
