import test from 'node:test';
import assert from 'node:assert/strict';
import {PebbleBridge, signedPost, signingKey, callbackURL} from '../src/worker.js';
const origin='https://pebble-test.example';
const secret='whsec_'+Buffer.alloc(32,7).toString('base64');
class Store {
  values=new Map();alarm=null;
  async get(k){return structuredClone(this.values.get(k));}
  async put(k,v){this.values.set(k,structuredClone(v));}
  async delete(k){this.values.delete(k);}
  async list({prefix}){return new Map([...this.values].filter(([k])=>k.startsWith(prefix)).map(([k,v])=>[k,structuredClone(v)]));}
  async setAlarm(value){this.alarm=value;}
}
async function digest(s){return Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))).toString('hex');}
function request(path,body,auth) {return new Request(origin+path,{method:body?'POST':'GET',headers:{...(body?{'Content-Type':'application/json'}:{}),...(auth?{Authorization:`Bearer ${auth}`}:{})},...(body?{body:JSON.stringify(body)}:{})});}
function fixture(){const store=new Store();return {store,bridge:new PebbleBridge({storage:store},{INGEST_TOKEN:'ingest-fixture',OWNER_PASSPHRASE_HASH:''})};}
async function oauth(bridge,store) {
  bridge.env.OWNER_PASSPHRASE_HASH=await digest('fixture-password');
  const redirect='https://chatgpt.com/connector_platform_oauth_redirect';
  const client=await (await bridge.fetch(request('/register',{redirect_uris:[redirect]}))).json();
  const verifier='a'.repeat(43),challenge=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))).toString('base64url');
  const query=new URLSearchParams({client_id:client.client_id,redirect_uri:redirect,response_type:'code',code_challenge_method:'S256',code_challenge:challenge,resource:origin+'/mcp',scope:'voice.read',state:'csrf-fixture'});
  const page=await bridge.fetch(new Request(origin+'/authorize?'+query));assert.equal(page.status,200);
  assert.match(page.headers.get('Content-Security-Policy'),/form-action 'self' https:\/\/chatgpt\.com;/);
  const flow=(await page.text()).match(/name="flow" value="([^"]+)"/)[1];
  const login=await bridge.fetch(new Request(origin+'/authorize',{method:'POST',body:new URLSearchParams({flow,passphrase:'fixture-password'})}));
  assert.equal(login.status,303);const location=new URL(login.headers.get('Location'));assert.equal(location.searchParams.get('state'),'csrf-fixture');
  const form={grant_type:'authorization_code',code:location.searchParams.get('code'),client_id:client.client_id,redirect_uri:redirect,resource:origin+'/mcp',code_verifier:verifier};
  const send=body=>bridge.fetch(new Request(origin+'/token',{method:'POST',body:new URLSearchParams(body)}));
  assert.equal((await send({...form,code_verifier:'b'.repeat(43)})).status,400);
  const response=await send(form);assert.equal(response.status,200);const token=await response.json();
  assert.equal((await send(form)).status,400);
  assert.equal((await bridge.fetch(request('/mcp',{jsonrpc:'2.0',id:1,method:'events/list'},token.access_token))).status,200);
  const refreshed=await send({grant_type:'refresh_token',refresh_token:token.refresh_token,client_id:client.client_id,resource:origin+'/mcp'});
  assert.equal(refreshed.status,200);return token.access_token;
}
test('OAuth discovery, private endpoints, PKCE, single-use code and token rotation',async()=>{
 const {bridge,store}=fixture();assert.equal((await bridge.fetch(request('/mcp'))).status,401);
 assert.equal((await bridge.fetch(request('/ingest',{id:'x',device:'pebble-index',text:'hello'}))).status,401);
 assert.equal((await bridge.fetch(request('/.well-known/oauth-protected-resource'))).status,200);
 assert.equal((await bridge.fetch(request('/register',{redirect_uris:['https://evil.example/callback']}))).status,400);
 await oauth(bridge,store);
});
test('callback scope, secret validity and Standard Webhooks signature',async()=>{
 for(const value of ['http://api.openai.com/x','https://127.0.0.1/x','https://api.openai.com.evil.example/x','https://user@chatgpt.com/x']) assert.throws(()=>callbackURL(value));
 assert.throws(()=>signingKey('whsec_AA=='));
 const event={eventId:'evt_fixture',name:'voice.transcribed',timestamp:new Date().toISOString(),data:{text:'こんにちは'},cursor:null};
 await signedPost({id:'sub_fixture',url:'https://api.openai.com/events',secret},event,async(url,opts)=>{
  assert.equal(opts.redirect,'error');const h=opts.headers;
  const key=await crypto.subtle.importKey('raw',signingKey(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);
  const sig=Buffer.from(h['webhook-signature'].slice(3),'base64');
  assert(await crypto.subtle.verify('HMAC',key,sig,new TextEncoder().encode(`${h['webhook-id']}.${h['webhook-timestamp']}.${opts.body}`)));
  return new Response('{}');
 });
});
test('subscription verification, persistence, duplicate ingestion, retries and unsubscribe',async()=>{
 const {bridge,store}=fixture();const token=await oauth(bridge,store),oldFetch=global.fetch;let deliveries=0;let failOnce=true;
 global.fetch=async(url,opts)=>{
  const data=JSON.parse(opts.body);
  if(data.type==='verification')return Response.json({challenge:data.challenge});
  deliveries++;if(failOnce){failOnce=false;return new Response('',{status:503});}return new Response('',{status:200});
 };
 try{
  const params={name:'voice.transcribed',arguments:{device:'pebble-index'},delivery:{mode:'webhook',url:'https://api.openai.com/events/test',secret}};
  const rpc=(method,p=params)=>bridge.fetch(request('/mcp',{jsonrpc:'2.0',id:1,method,params:p},token));
  const first=await (await rpc('events/subscribe')).json();assert(first.result.id);
  const again=await (await rpc('events/subscribe')).json();assert.equal(first.result.id,again.result.id);
  const body={id:'recording_fixture',device:'pebble-index',text:'マイクのテスト中。'};
  const ingested=await (await bridge.fetch(request('/ingest',body,'ingest-fixture'))).json();assert.equal(ingested.subscriptions,1);
  assert((await (await bridge.fetch(request('/ingest',body,'ingest-fixture'))).json()).duplicate);
  assert.equal((await store.list({prefix:'job:'})).size,1);
  const restarted=new PebbleBridge({storage:store},bridge.env);await restarted.alarm();assert.equal(deliveries,1);
  for(const [k,v] of await store.list({prefix:'job:'})){v.due=0;await store.put(k,v);}
  await restarted.alarm();assert.equal(deliveries,2);assert.equal((await store.list({prefix:'job:'})).size,0);
  assert((await (await rpc('events/unsubscribe')).json()).result);
  assert.equal((await store.list({prefix:'sub:'})).size,0);
 }finally{global.fetch=oldFetch;}
});
