# PowerLine serverless environment

Configure these as protected Twilio Function environment variables. Never
commit their values:

- `ELEVENLABS_API_KEY`
- `ELEVENLABS_VOICE_ID` — the private **Arpita bb** voice ID
- `POWERLINE_FROM_NUMBER` — the active Twilio DID in E.164 format
- `TWIML_APP_SID`
- `TWILIO_API_KEY_SID`
- `TWILIO_API_KEY_SECRET`

The GitHub repository intentionally contains no voice recording, cloned voice
artifact, API credential, or private Voice ID.
