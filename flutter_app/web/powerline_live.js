(() => {
  let device, activeCall, notify, pending = false, disposed = false;
  let retryTimer, retries = 0;
  const attempts = new Map();
  const emit = (type, fields = {}) => { if (!disposed && notify) notify(JSON.stringify({type, ...fields})); };
  async function api(method, path, input) {
    if (!path.startsWith('/api/')) throw Error('Invalid API path');
    const url = new URL(path, location.origin);
    if (url.origin !== location.origin) throw Error('Same-origin API required');
    const headers = {Accept: 'application/json'};
    if (input) headers['Content-Type'] = 'application/json';
    let attempt;
    if (method === 'POST' && path === '/api/messages') {
      attempt = JSON.stringify(input);
      if (!attempts.has(attempt)) attempts.set(attempt, crypto.randomUUID());
      headers['Idempotency-Key'] = attempts.get(attempt);
    }
    const response = await fetch(url, {method, headers, credentials: 'same-origin', cache: 'no-store', ...(input ? {body: JSON.stringify(input)} : {})});
    let data;
    try {data = await response.json();} catch {throw Error('Sign in to the protected PowerLine workspace and reload.');}
    if (!response.ok) throw Error(data.error || `Service returned ${response.status}`);
    if (attempt) attempts.delete(attempt);
    return data;
  }
  window.powerlineLiveRequest = async (method, path, body) => JSON.stringify(await api(method, path, body ? JSON.parse(body) : undefined));
  function bindCall(call, direction, remote) {
    activeCall = call;
    const id = call.parameters?.CallSid || crypto.randomUUID();
    const state = value => emit('call', {id, state: value, direction, remote});
    state(direction === 'inbound' ? 'incoming' : 'dialing');
    call.on('ringing', () => state('ringing'));
    call.on('accept', () => state('connected'));
    const end = value => { if (activeCall === call) activeCall = undefined; state(value); };
    call.on('disconnect', () => end('completed'));
    call.on('cancel', () => end('canceled'));
    call.on('reject', () => end('rejected'));
    call.on('error', error => {emit('error', {message: error.message || 'Call failed'}); end('failed');});
    if (call.status() === 'open') state('connected');
    return id;
  }
  window.powerlineLiveInitialize = async callback => {
    if (device) return 'ready';
    disposed = false; notify = callback;
    const payload = await api('GET', '/api/voice/token');
    const current = new Twilio.Device(payload.token, {closeProtection: true, codecPreferences: ['opus', 'pcmu'], tokenRefreshMs: 60000});
    device = current;
    current.on('registered', () => {retries = 0; emit('registration', {state: 'ready'});});
    current.on('unregistered', () => {
      emit('registration', {state: 'offline'});
      if (!disposed && current === device && retries < 3) {
        retryTimer = setTimeout(async () => {try {retries++; await current.register();} catch (error) {emit('error', {message: error.message});}}, Math.min(30000, 2000 * 2 ** retries));
      }
    });
    current.on('error', error => emit('error', {message: error.message || 'Voice connection failed'}));
    current.on('tokenWillExpire', async () => {
      try {current.updateToken((await api('GET', '/api/voice/token')).token);} catch (error) {emit('registration', {state: 'offline'}); emit('error', {message: error.message});}
    });
    current.on('incoming', call => {
      if (activeCall || pending) {call.reject(); return;}
      bindCall(call, 'inbound', call.parameters?.From || 'Unknown caller');
    });
    try {await current.register();} catch (error) {current.destroy(); if (device === current) device = undefined; throw error;}
    return 'ready';
  };
  window.powerlineLiveCall = async (numberId, to) => {
    if (!device || activeCall || pending) throw Error('Connect calling first and finish the current call.');
    pending = true;
    try {
      const intent = await api('POST', '/api/voice/intent', {number_id: numberId, to});
      return bindCall(await device.connect({params: {To: to, CallGrant: intent.grant}}), 'outbound', to);
    } finally {pending = false;}
  };
  window.powerlineLiveAnswer = () => {if (!activeCall) throw Error('No incoming call'); activeCall.accept();};
  window.powerlineLiveReject = () => {if (activeCall) activeCall.reject();};
  window.powerlineLiveHangup = () => {if (activeCall) activeCall.disconnect();};
  window.powerlineLiveMute = value => {if (activeCall) activeCall.mute(Boolean(value));};
  window.powerlineLiveDigits = value => {if (!/^[0-9*#w]{1,32}$/.test(value)) throw Error('Invalid keypad digits'); if (activeCall) activeCall.sendDigits(value);};
  window.powerlineLiveDispose = () => {
    disposed = true; clearTimeout(retryTimer);
    if (activeCall) activeCall.disconnect();
    activeCall = undefined;
    if (device) device.destroy();
    device = undefined; notify = undefined; pending = false; retries = 0;
  };
})();
