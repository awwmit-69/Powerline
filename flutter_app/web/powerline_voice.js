// Self-hosted PowerLine voice bridge (neutral filename avoids browser blocking).
//
// Security model:
// - The agent signs in once with Agent ID + PIN (server: /auth-verify; PINs live
//   only in the server's AGENT_PINS setting).
// - The signed session is kept in this browser until it expires (server
//   SESSION_TTL_SECONDS) and is exchanged for 1-hour Twilio voice tokens
//   (/voice-token). Sign out clears it.
// - No Twilio secrets ever reach the browser.
//
// POWERLINE_VOICE_TOKEN_URL must be https://<service>.twil.io/voice-token;
// the auth endpoints are resolved relative to it.
(() => {
  const SESSION_KEY = "powerline.agentSession";

  let device;
  let tokenUrl;
  let apiBase;
  let stateCallback;
  let errorCallback;
  let incomingCallback;
  const calls = new Map(); // callId -> Twilio Call
  let activeCallId;

  const emitState = (state, callId) => {
    if (stateCallback) stateCallback(state, callId || "");
  };

  const emitError = (error) => {
    const message = error && error.message ? error.message : String(error);
    if (errorCallback) errorCallback(message);
  };

  // ---------- session ----------
  const store = (() => {
    try {
      localStorage.setItem("powerline.probe", "1");
      localStorage.removeItem("powerline.probe");
      return localStorage;
    } catch (_) {
      return sessionStorage;
    }
  })();

  function loadSession() {
    try {
      const raw = store.getItem(SESSION_KEY);
      if (!raw) return null;
      const s = JSON.parse(raw);
      if (!s.session || !s.expiresAt || s.expiresAt * 1000 < Date.now() + 60000) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  function saveSession(s) {
    try {
      store.setItem(SESSION_KEY, JSON.stringify(s));
    } catch (_) {
      // Storage unavailable: session lives only in memory for this page.
    }
    memorySession = s;
  }

  function clearSession() {
    memorySession = null;
    try {
      store.removeItem(SESSION_KEY);
    } catch (_) {}
  }

  let memorySession = null;
  const currentSession = () => loadSession() || memorySession;

  async function post(path, fields) {
    const body = new URLSearchParams(fields);
    // Form-encoded body + no custom headers = simple CORS request (no preflight).
    const res = await fetch(`${apiBase}/${path}`, { method: "POST", body, cache: "no-store" });
    let payload = {};
    try {
      payload = await res.json();
    } catch (_) {}
    return { ok: res.ok, status: res.status, payload };
  }

  // ---------- sign-in dialog (Agent ID + PIN, one step) ----------
  function signInDialog() {
    return new Promise((resolve, reject) => {
      const css = {
        overlay: "position:fixed;inset:0;background:rgba(11,27,43,.78);display:flex;align-items:center;justify-content:center;z-index:2147483647;font-family:Manrope,system-ui,sans-serif",
        card: "background:#102A40;border:1px solid #243444;border-radius:16px;padding:24px;width:min(360px,92vw);color:#F4F2EC;box-shadow:0 20px 60px rgba(0,0,0,.45)",
        input: "width:100%;box-sizing:border-box;margin:6px 0 14px;padding:11px 12px;border-radius:10px;border:1px solid #243444;background:#0B1B2B;color:#F4F2EC;font-size:15px",
        primary: "width:100%;padding:11px;border:0;border-radius:10px;background:#2C6BFF;color:#fff;font-weight:700;font-size:15px;cursor:pointer",
        link: "background:none;border:0;color:#AEB9C7;cursor:pointer;margin-top:10px;font-size:13px",
      };
      const overlay = document.createElement("div");
      overlay.setAttribute("style", css.overlay);
      overlay.innerHTML = `
        <form style="${css.card}" autocomplete="on">
          <div style="font-weight:800;font-size:18px;margin-bottom:4px">PowerLine sign-in</div>
          <div style="color:#AEB9C7;font-size:13px;margin-bottom:14px">Sign in once. This browser stays signed in and rings for calls.</div>
          <label style="font-size:12px;color:#AEB9C7">Agent ID</label>
          <input data-k="agent" name="username" autocomplete="username" style="${css.input}" autocapitalize="off" spellcheck="false" required>
          <label style="font-size:12px;color:#AEB9C7">PIN</label>
          <input data-k="pin" name="password" type="password" autocomplete="current-password" style="${css.input}" maxlength="10" required>
          <div data-k="err" style="color:#E5675A;font-size:13px;min-height:18px;margin-bottom:8px"></div>
          <button data-k="go" type="submit" style="${css.primary}">Sign in</button>
          <button data-k="cancel" type="button" style="${css.link}">Cancel</button>
        </form>`;
      document.body.appendChild(overlay);
      const $ = (k) => overlay.querySelector(`[data-k="${k}"]`);
      const close = () => overlay.remove();
      try {
        const last = store.getItem("powerline.lastAgent");
        if (last) $("agent").value = last;
      } catch (_) {}

      $("cancel").onclick = () => {
        close();
        reject(new Error("Sign-in cancelled"));
      };
      overlay.querySelector("form").onsubmit = async (e) => {
        e.preventDefault();
        $("err").textContent = "";
        $("go").disabled = true;
        $("go").textContent = "Signing in…";
        const agent = $("agent").value.trim().toLowerCase();
        const pin = $("pin").value.trim();
        try {
          const r = await post("auth-verify", { agent, code: pin });
          if (!r.ok || !r.payload.session) throw new Error("Wrong Agent ID or PIN.");
          saveSession(r.payload);
          try {
            store.setItem("powerline.lastAgent", agent);
          } catch (_) {}
          close();
          resolve(r.payload);
        } catch (err) {
          $("err").textContent = err.message || "Sign-in failed. Check your connection.";
        } finally {
          $("go").disabled = false;
          $("go").textContent = "Sign in";
        }
      };
      ($("agent").value ? $("pin") : $("agent")).focus();
    });
  }

  async function ensureSession() {
    return currentSession() || (await signInDialog());
  }

  async function fetchToken() {
    let s = await ensureSession();
    let r = await post("voice-token", { session: s.session });
    if (r.status === 401) {
      clearSession();
      s = await signInDialog();
      r = await post("voice-token", { session: s.session });
    }
    if (!r.ok || !r.payload.token) throw new Error(`Token service returned ${r.status}`);
    return r.payload.token;
  }

  // ---------- call wiring ----------
  function wireCall(call, callId) {
    calls.set(callId, call);
    const done = (state) => {
      emitState(state, callId);
      calls.delete(callId);
      if (activeCallId === callId) activeCallId = undefined;
    };
    call.on("ringing", () => emitState("ringing", callId));
    call.on("accept", () => {
      activeCallId = callId;
      emitState("connected", callId);
    });
    call.on("disconnect", () => done("completed"));
    call.on("cancel", () => done("completed"));
    call.on("reject", () => done("failed"));
    call.on("error", (error) => {
      emitError(error);
      done("failed");
    });
  }

  window.powerlineTwilioInitialize = async (url, onState, onError, onIncoming) => {
    tokenUrl = url;
    apiBase = String(url).replace(/\/voice-token\/?$/, "");
    stateCallback = onState;
    errorCallback = onError;
    incomingCallback = onIncoming;

    if (device) return "ready";
    if (typeof Twilio === "undefined" || !Twilio.Device) {
      throw new Error("Twilio Voice SDK failed to load");
    }

    const token = await fetchToken();
    device = new Twilio.Device(token, {
      closeProtection: true,
      codecPreferences: ["opus", "pcmu"],
      // Nearest edges first for agents in South Asia, then US East.
      edge: ["singapore", "ashburn"],
    });
    device.on("error", emitError);
    device.on("tokenWillExpire", async () => {
      try {
        device.updateToken(await fetchToken());
      } catch (error) {
        emitError(error);
      }
    });
    device.on("incoming", (call) => {
      const callId = `twilio_in_${Date.now()}`;
      if (activeCallId) {
        call.reject(); // busy: let other devices / voicemail take it
        return;
      }
      wireCall(call, callId);
      const from = (call.parameters && call.parameters.From) || "unknown";
      if (incomingCallback) incomingCallback(callId, from);
    });
    await device.register();
    return "ready";
  };

  window.powerlineTwilioPlaceCall = async (destination) => {
    if (!device) throw new Error("Twilio device is not initialized");
    if (activeCallId) throw new Error("A call is already active");

    const callId = `twilio_${Date.now()}`;
    emitState("dialing", callId);
    const call = await device.connect({ params: { To: destination } });
    activeCallId = callId;
    wireCall(call, callId);
    return callId;
  };

  // ---------- AI agent call (Maya) — consent-gated ----------
  function aiCallDialog(destination) {
    return new Promise((resolve, reject) => {
      const input = "width:100%;box-sizing:border-box;margin:6px 0 12px;padding:10px 12px;border-radius:10px;border:1px solid #243444;background:#0B1B2B;color:#F4F2EC;font-size:14px";
      const overlay = document.createElement("div");
      overlay.setAttribute("style", "position:fixed;inset:0;background:rgba(11,27,43,.78);display:flex;align-items:center;justify-content:center;z-index:2147483647;font-family:Manrope,system-ui,sans-serif");
      const today = new Date().toISOString().slice(0, 10);
      overlay.innerHTML = `
        <form style="background:#102A40;border:1px solid #243444;border-radius:16px;padding:22px;width:min(380px,92vw);color:#F4F2EC">
          <div style="font-weight:800;font-size:18px">AI call: Maya</div>
          <div style="color:#AEB9C7;font-size:13px;margin:4px 0 14px">Maya calls <b>${destination}</b> in her AI voice. Only call leads who gave written consent to AI calls.</div>
          <label style="font-size:12px;color:#AEB9C7">First name (optional)</label>
          <input data-k="first" style="${input}" maxlength="40">
          <label style="font-size:12px;color:#AEB9C7">Service</label>
          <select data-k="vertical" style="${input}">
            <option value="roofing">Roofing</option><option value="solar">Solar</option>
            <option value="insurance">Insurance</option><option value="hvac">HVAC</option>
            <option value="general">General</option>
          </select>
          <label style="font-size:12px;color:#AEB9C7">Where consent was given</label>
          <input data-k="source" style="${input}" placeholder="e.g. roofquote.com form" required minlength="3">
          <label style="font-size:12px;color:#AEB9C7">Consent date</label>
          <input data-k="date" type="date" style="${input}" value="${today}" max="${today}" required>
          <label style="display:flex;gap:8px;font-size:13px;align-items:flex-start;margin-bottom:12px">
            <input data-k="ok" type="checkbox" required style="margin-top:2px">
            <span>This lead gave prior express written consent to AI/automated calls from us.</span>
          </label>
          <div data-k="err" style="color:#E5675A;font-size:13px;min-height:18px;margin-bottom:8px"></div>
          <button data-k="go" type="submit" style="width:100%;padding:11px;border:0;border-radius:10px;background:#2C6BFF;color:#fff;font-weight:700;font-size:15px;cursor:pointer">Have Maya call</button>
          <button data-k="cancel" type="button" style="background:none;border:0;color:#AEB9C7;cursor:pointer;margin-top:10px;font-size:13px">Cancel</button>
        </form>`;
      document.body.appendChild(overlay);
      const $ = (k) => overlay.querySelector(`[data-k="${k}"]`);
      $("cancel").onclick = () => { overlay.remove(); reject(new Error("cancelled")); };
      overlay.querySelector("form").onsubmit = async (e) => {
        e.preventDefault();
        $("err").textContent = "";
        $("go").disabled = true;
        $("go").textContent = "Starting…";
        try {
          let s = await ensureSession();
          const fields = () => ({
            session: s.session,
            to: destination,
            first_name: $("first").value.trim(),
            vertical: $("vertical").value,
            consent_source: $("source").value.trim(),
            consent_timestamp: `${$("date").value}T12:00:00Z`,
            tz: Intl.DateTimeFormat().resolvedOptions().timeZone || "America/New_York",
          });
          let r = await post("ai-call", fields());
          if (r.status === 401) {
            clearSession();
            s = await signInDialog();
            r = await post("ai-call", fields());
          }
          if (!r.ok) {
            const map = {
              ai_outbound_disabled: "AI calling is switched off on the server.",
              consent_required: "Consent source and date are required.",
              do_not_call: "That number is on the Do-Not-Call list.",
              outside_calling_hours: "Outside calling hours (8am–9pm lead time).",
              bad_destination: (r.payload && r.payload.message) || "That number can't be called.",
            };
            throw new Error(map[r.payload && r.payload.error] || "Could not start the AI call.");
          }
          overlay.remove();
          resolve(r.payload.callSid || "started");
        } catch (err) {
          $("err").textContent = err.message || "Could not start the AI call.";
        } finally {
          $("go").disabled = false;
          $("go").textContent = "Have Maya call";
        }
      };
      $("source").focus();
    });
  }

  // ---------- Appointments panel ----------
  function esc(v) {
    return String(v == null ? "" : v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  async function appointmentsPanel() {
    const overlay = document.createElement("div");
    overlay.setAttribute("style", "position:fixed;inset:0;background:rgba(11,27,43,.78);display:flex;align-items:center;justify-content:center;z-index:2147483647;font-family:Manrope,system-ui,sans-serif");
    overlay.innerHTML = `
      <div style="background:#102A40;border:1px solid #243444;border-radius:16px;padding:20px;width:min(560px,94vw);max-height:86vh;display:flex;flex-direction:column;color:#F4F2EC">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">
          <div style="font-weight:800;font-size:18px">Appointments</div>
          <div><button data-k="refresh" style="background:#243444;border:0;color:#F4F2EC;border-radius:8px;padding:6px 10px;cursor:pointer;margin-right:6px">Refresh</button>
          <button data-k="close" style="background:none;border:0;color:#AEB9C7;cursor:pointer;font-size:14px">Close</button></div>
        </div>
        <div data-k="list" style="overflow:auto;flex:1;font-size:14px">Loading…</div>
      </div>`;
    document.body.appendChild(overlay);
    const $ = (k) => overlay.querySelector(`[data-k="${k}"]`);
    $("close").onclick = () => overlay.remove();

    async function load() {
      $("list").textContent = "Loading…";
      let s = await ensureSession();
      let r = await post("appt-list", { session: s.session });
      if (r.status === 401) {
        clearSession();
        s = await signInDialog();
        r = await post("appt-list", { session: s.session });
      }
      if (!r.ok) {
        $("list").textContent = "Could not load appointments.";
        return;
      }
      const items = r.payload.appointments || [];
      if (!items.length) {
        $("list").innerHTML = `<div style="color:#AEB9C7;padding:12px 0">No upcoming appointments yet.</div>`;
        return;
      }
      $("list").innerHTML = items
        .map(
          (a) => `
        <div style="border:1px solid #243444;border-radius:12px;padding:12px;margin-bottom:10px">
          <div style="display:flex;justify-content:space-between;gap:8px">
            <div style="font-weight:700">${esc(a.label)}</div>
            <span style="background:#243444;border-radius:6px;padding:2px 8px;font-size:12px;text-transform:capitalize">${esc(a.vertical)}</span>
          </div>
          <div style="margin-top:6px">${esc(a.name)} · <a href="tel:${esc(a.phone)}" style="color:#7FB2FF">${esc(a.phone)}</a></div>
          <div style="color:#AEB9C7">${esc(a.address)} ${esc(a.zip)}</div>
          ${a.notes ? `<div style="color:#AEB9C7;margin-top:4px;font-size:13px">${esc(a.notes)}</div>` : ""}
          <div style="margin-top:8px;display:flex;justify-content:space-between;align-items:center">
            <span style="color:#6E7F92;font-size:12px">Booked by ${esc(a.source || "maya")}</span>
            <button data-cancel="${esc(a.key)}" style="background:none;border:1px solid #E5675A;color:#E5675A;border-radius:8px;padding:4px 10px;cursor:pointer;font-size:12px">Cancel</button>
          </div>
        </div>`,
        )
        .join("");
      overlay.querySelectorAll("[data-cancel]").forEach((b) => {
        b.onclick = async () => {
          if (b.dataset.confirm !== "1") {
            b.dataset.confirm = "1";
            b.textContent = "Tap again to cancel";
            return;
          }
          b.disabled = true;
          const s2 = await ensureSession();
          const rr = await post("appt-list", { session: s2.session, action: "cancel", key: b.dataset.cancel });
          if (rr.ok) await load();
          else b.textContent = "Cancel failed";
        };
      });
    }
    $("refresh").onclick = load;
    await load();
    return "opened";
  }

  window.powerlineAppointments = async (url) => {
    if (!apiBase && url) apiBase = String(url).replace(/\/voice-token\/?$/, "");
    if (!apiBase) throw new Error("PowerLine server is not configured");
    return appointmentsPanel();
  };

  window.powerlineAiCall = async (destination, url) => {
    if (!apiBase && url) apiBase = String(url).replace(/\/voice-token\/?$/, "");
    if (!apiBase) throw new Error("PowerLine server is not configured");
    return aiCallDialog(destination);
  };

  window.powerlineTwilioAccept = (callId) => {
    const call = calls.get(callId);
    if (call) call.accept();
  };

  window.powerlineTwilioReject = (callId) => {
    const call = calls.get(callId);
    if (call) call.reject();
  };

  const active = () => (activeCallId ? calls.get(activeCallId) : undefined);

  window.powerlineTwilioHangup = () => {
    const call = active();
    if (call) call.disconnect();
  };

  window.powerlineTwilioMute = (muted) => {
    const call = active();
    if (call) call.mute(Boolean(muted));
  };

  window.powerlineTwilioSendDigits = (digits) => {
    const call = active();
    if (call) call.sendDigits(digits);
  };

  window.powerlineTwilioHasSession = () => Boolean(currentSession());

  window.powerlineTwilioSignOut = () => {
    clearSession();
    window.powerlineTwilioDispose();
  };

  window.powerlineTwilioDispose = () => {
    if (device) device.destroy();
    calls.clear();
    activeCallId = undefined;
    device = undefined;
  };
})();
