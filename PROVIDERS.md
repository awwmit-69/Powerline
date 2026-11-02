# Provider decision — reviewed November 2, 2026

Initial choice: Twilio, because the existing Flutter project already contains its
browser SDK bridge. This reduces integration work; it does not mean that the
existing bridge is complete or verified. No provider account was changed.

Published USD list prices, before tax, surcharges and registration unless stated:

| Provider | Number rental | Voice | SMS | Integration consequence |
| --- | --- | --- | --- | --- |
| Twilio | US local $1.15/month | Local outgoing $0.014/min; incoming $0.0085/min; browser/app leg $0.004/min | Obtain account-specific messaging and carrier rates before approval | Best fit for existing browser bridge; secure token issuer and TwiML still required |
| SignalMash Launch | Obtain number quote | Voice API US lower 48 zone 1 outgoing $0.0086/min; local inbound $0.0071/min | $0.0039 send/receive; published SMS plan lists $19/month platform fee and $19 onboarding | Voice and messages APIs exist; confirm browser media transport and webhook verification before adapter work |
| VoIP.ms | Local starting $1.10/month and $0.40 setup | Outgoing from $0.005/min; inbound from $0.009/min | $0.0075 send/receive; MMS $0.02 | SIP voice and REST control/messaging; portal API enablement and IP whitelist required |

Example Twilio estimate: one local number, 100 outbound and 100 inbound minutes,
with one browser SDK leg per call minute: $1.15 + $1.40 + $0.85 + $0.80 =
$4.20/month before SMS, taxes, registrations, recordings and other features.
This is an engineering estimate from published line items, not an account quote.

SignalMash Launch's published SMS plan lists basic brand vetting $25 once and
low mixed-use campaign $5/month. Confirm account applicability and voice/number
fees directly. No paid plan or promotional credit has been activated.

VoIP.ms explicitly documents sendSMS/sendMMS and business verification; its API
uses whitelisted source IPs. A Worker deployment must establish a supported
egress strategy rather than assuming a stable outbound IP. Browser calling also
needs a validated SIP/WebRTC path; REST call control alone does not provide audio.

Keep provider credentials behind a server adapter. The initial Worker currently
implements only Twilio SMS and rejects numbers assigned to another adapter.
SignalMash and VoIP.ms remain evaluated options, not implemented integrations.

Cloud infrastructure has no provisioned PowerLine resources in this change.
Free-tier eligibility and actual account limits must be checked before deployment.
There are no confirmed startup or Brex credits applied to this project.

Sources:

- https://www.twilio.com/en-us/voice/pricing/us
- https://www.twilio.com/docs/voice/pricing
- https://signalmash.com/pricing
- https://doc.signalmash.com/ (use POST /messages; older /sms and /mms deprecated)
- https://voip.ms/pricing
- https://wiki.voip.ms/article/API_Overview
- https://wiki.voip.ms/article/FAQ
