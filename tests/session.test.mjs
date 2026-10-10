import test from 'node:test';
import assert from 'node:assert/strict';
import {api} from '../public/shared.js';
test('concurrent admin requests refresh once and never refresh after sign-out',async()=>{
 const originalFetch=globalThis.fetch,originalStorage=globalThis.sessionStorage;
 const saved=new Map();globalThis.sessionStorage={getItem:k=>saved.get(k)||null,setItem:(k,v)=>saved.set(k,v),removeItem:k=>saved.delete(k)};
 try{
  sessionStorage.setItem('drvn-session',JSON.stringify({access_token:'expired-test',refresh_token:'test-refresh',expires_at:0}));
  let refreshes=0;
  globalThis.fetch=async(url)=>{if(String(url).includes('grant_type=refresh_token')){refreshes++;await new Promise(r=>setTimeout(r,5));return Response.json({access_token:'fresh-test',refresh_token:'next-test',expires_in:3600});}return Response.json({ok:true});};
  const results=await Promise.all([api('workspace',{},true),api('admin_list',{},true)]);
  assert.equal(refreshes,1);assert.ok(results.every(x=>x.ok));
  sessionStorage.setItem('drvn-session',JSON.stringify({access_token:'expired-test',refresh_token:'test-refresh',expires_at:0}));
  globalThis.fetch=async()=>{sessionStorage.removeItem('drvn-session');return Response.json({access_token:'late-test',refresh_token:'late-refresh',expires_in:3600});};
  await assert.rejects(api('workspace',{},true),/signed out/);assert.equal(sessionStorage.getItem('drvn-session'),null);
 }finally{globalThis.fetch=originalFetch;globalThis.sessionStorage=originalStorage;}
});
test('non-JSON server errors become readable messages',async()=>{
 const originalFetch=globalThis.fetch;try{globalThis.fetch=async()=>new Response('<h1>Gateway error</h1>',{status:502});await assert.rejects(api('events'),/unexpected response/);}finally{globalThis.fetch=originalFetch;}
});
