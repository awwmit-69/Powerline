import {authenticate,base64url,bytes64,fail,readJson,hmac} from './security.mjs';
const q=(env,sql,...args)=>env.DB.prepare(sql).bind(...args);
const cookie='__Host-powerline_session';
const encode=value=>new TextEncoder().encode(value);
export async function digest(value){return base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',encode(value))));}
export async function usernameHash(value,pepper){return base64url(await hmac(pepper,'username:'+value));}
export async function passwordHash(password,salt,pepper){
  const material=await hmac(pepper,'password:'+password);
  const key=await crypto.subtle.importKey('raw',material,'PBKDF2',false,['deriveBits']);
  return base64url(new Uint8Array(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:bytes64(salt),iterations:100000},key,256)));
}
function secureEqual(a,b){let difference=a.length^b.length;for(let i=0;i<Math.max(a.length,b.length);i++)difference|=(a.charCodeAt(i)||0)^(b.charCodeAt(i)||0);return difference===0;}
function sessionToken(request){
  const value=(request.headers.get('Cookie')||'').split(';').map(x=>x.trim()).find(x=>x.startsWith(cookie+'='))?.slice(cookie.length+1);
  return value&&/^[\w-]{43}$/.test(value)?value:null;
}
function sessionCookie(token,age=28800){return `${cookie}=${token}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=${age}`;}
export async function currentUser(request,env){
  if(!env.DB)fail(503,'Storage not configured');
  if(env.AUTH_MODE!=='password'){
    const claims=await authenticate(request,env);
    const user=await q(env,'SELECT * FROM users WHERE email=? AND active=1',claims.email.toLowerCase()).first();
    if(!user)fail(403,'User has not been invited');return user;
  }
  const token=sessionToken(request);if(!token)fail(401,'Sign in required');
  const user=await q(env,'SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id JOIN credentials c ON c.user_id=u.id WHERE s.token_hash=? AND s.expires_at>unixepoch() AND s.credential_version=c.version AND u.active=1',await digest(token)).first();
  if(!user)fail(401,'Session expired. Sign in again.');return user;
}
export async function authRoute(request,env,path){
  if(env.AUTH_MODE!=='password'||!env.AUTH_PEPPER||!env.DB)fail(503,'Password sign-in is not configured');
  if(request.method!=='POST')fail(405,'POST required');
  const body=await readJson(request,env);
  if(path==='/api/auth/logout'){
    const token=sessionToken(request);
    if(token)await q(env,'DELETE FROM sessions WHERE token_hash=?',await digest(token)).run();
    return new Response(null,{status:204,headers:{'Set-Cookie':sessionCookie('',0),'Cache-Control':'no-store'}});
  }
  if(typeof body.username!=='string'||typeof body.password!=='string'||body.username.length<1||body.username.length>100||body.password.length<1||body.password.length>200)fail(400,'Enter your username and password');
  const username=await usernameHash(body.username,env.AUTH_PEPPER);
  const window=Math.floor(Date.now()/900000);
  const ip=await usernameHash('ip:'+(request.headers.get('CF-Connecting-IP')||'unknown'),env.AUTH_PEPPER);
  // Persist both per-account and per-IP throttles before performing expensive KDF work.
  for(const [key,max]of [[username,8],[ip,30]]){
    const row=await q(env,'INSERT INTO login_limits(key,window,count) VALUES(?,?,1) ON CONFLICT(key,window) DO UPDATE SET count=count+1 RETURNING count',key,window).first();
    if(row.count>max)fail(429,'Too many sign-in attempts. Try again later.');
  }
  const credential=await q(env,'SELECT c.*,u.active FROM credentials c JOIN users u ON u.id=c.user_id WHERE c.username_hash=?',username).first();
  const salt=credential?.salt||'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  const computed=await passwordHash(body.password,salt,env.AUTH_PEPPER);
  if(!credential||credential.active!==1||!secureEqual(computed,credential.password_hash))fail(401,'Username or password is incorrect');
  const token=base64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.DB.batch([
    q(env,'INSERT INTO sessions(token_hash,user_id,credential_version,expires_at) VALUES(?,?,?,unixepoch()+28800)',await digest(token),credential.user_id,credential.version),
    q(env,"INSERT INTO audit_logs(user_id,action,resource_id) VALUES(?,'auth.login',?)",credential.user_id,credential.user_id),
    q(env,'DELETE FROM sessions WHERE expires_at<unixepoch()'),
    q(env,'DELETE FROM login_limits WHERE window<?',window-2)
  ]);
  return new Response(JSON.stringify({ok:true}),{headers:{'Content-Type':'application/json','Cache-Control':'no-store','Set-Cookie':sessionCookie(token)}});
}
