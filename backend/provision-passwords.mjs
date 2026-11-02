// Run locally; outputs private bootstrap files outside the repository.
import {randomBytes} from 'node:crypto';
import {writeFile,readFile,mkdir} from 'node:fs/promises';
import {join} from 'node:path';
import {passwordHash,usernameHash} from './password-auth.mjs';
const directory=process.argv[2],delivery=process.argv[3];
if(!directory||!delivery)throw Error('Private directory and credential delivery path required');
await mkdir(directory,{recursive:true,mode:0o700});
const path=join(directory,'bootstrap.json');let data;
try{data=JSON.parse(await readFile(path,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
if(!data){
  data={pepper:randomBytes(32).toString('base64url'),accounts:[]};
  for(const id of ['owner','agent01','agent02','agent03','agent04']){
    const username='pl_'+randomBytes(18).toString('base64url');
    const salt=randomBytes(32).toString('base64url');
    data.accounts.push({id,username,password:username,salt,username_hash:await usernameHash(username,data.pepper),password_hash:await passwordHash(username,salt,data.pepper)});
  }
  await writeFile(path,JSON.stringify(data),{mode:0o600,flag:'wx'});
}
let text='POWERLINE — PRIVATE LOGIN DETAILS\n\nSign in: https://powerline.azdglobal.com/login\nTwilio owner setup: https://powerline.azdglobal.com/setup/twilio\n\nEach account has a unique random username. Its initial password is the same value, as requested. Keep both private.\n\n';
for(const a of data.accounts)text+=`Account: ${a.id}\nUsername: ${a.username}\nPassword: ${a.password}\nRole: ${a.id==='owner'?'Administrator':'Agent'}\n\n`;
text+='Agent accounts start with no assigned telephone numbers. The owner assigns lines in Team logins.\n\nThe phone service is not connected until the owner enters Twilio credentials and configures an owned number. This file does not contain Twilio credentials.\n';
await writeFile(delivery,text,{mode:0o600});
console.log('Prepared five private account credentials; values were not printed.');
