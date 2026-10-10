import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {JSDOM} from 'jsdom';
import {escape,peso,date,label} from '../public/shared.js';
import {workspaceTabs,categoryRows,workspaceMetrics} from '../public/tournament.js';
const source=fs.readFileSync(new URL('../public/admin.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').split("if(document.body.dataset.page==='login')")[0];
const ids=['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'];
const tournaments=ids.map((id,i)=>({id,title:`Event ${i+1}`,starts_at:'2027-01-05T08:00:00Z',venue:'Test court',status:'published',gallery:[]}));
const summary={registrations:1,confirmed:1,confirmed_players:2,waitlisted:0,available:9,pending:0,collections:10000,refunds:0,categories:[{id:'category',name:'Doubles',unit:'team',capacity:10,occupied:1,confirmed:1,confirmed_players:2,waitlisted:0,fee_cents:10000,active:true}],statuses:{confirmed:1}};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function harness(override){
 const dom=new JSDOM(fs.readFileSync(new URL('../public/admin/index.html',import.meta.url),'utf8'));
 const document=dom.window.document,calls=[];
 const api=async(action,body={})=>{calls.push({action,body});if(override){const out=override(action,body);if(out!==undefined)return out;}if(action==='workspace')return {organizer:'test@example.test',summary:{registrations:2,pending:0,collections:20000,upcoming:2},tournaments,categories:[],settings:[]};if(action==='tournament_summary')return summary;if(action==='admin_list')return {total:1,rows:[{id:'registration',player_name:body.event===ids[0]?'Alice':'Bob',email:'test@example.test',partner_name:'Partner',tournament_title:body.event===ids[0]?'Event 1':'Event 2',category_name:'Doubles',unit:'team',status:'confirmed',payment_status:'verified',amount_due:10000}]};return {};};
 const context=vm.createContext({document,$:s=>document.querySelector(s),e:escape,peso,date,label,api,workspaceTabs,categoryRows,workspaceMetrics,message:()=>{},busy:()=>{},crypto:globalThis.crypto,URL,Blob,setTimeout,console,prompt:()=>null});
 vm.runInContext(source,context);
 return {context,document,calls,run:s=>vm.runInContext(s,context),close:()=>dom.window.close()};
}
test('workspace tabs preserve event scope, filters, global navigation and editor return',async()=>{
 const h=harness();try{await h.run('load()');h.run(`openTournament('${ids[0]}')`);await tick();assert.equal(h.document.querySelector('#page-title').textContent,'Event 1');assert.equal(h.document.querySelectorAll('.workspace-tabs button').length,7);
 for(const tab of workspaceTabs){h.run(`openTournament('${ids[0]}','${tab}')`);await tick();assert.ok(h.document.querySelector('#tournament-content'));assert.equal(h.document.querySelector('#event-filter'),null);}
 h.run(`openTournament('${ids[0]}','Players')`);await tick();assert.match(h.document.querySelector('#records').textContent,/Alice/);assert.equal(h.calls.at(-1).body.filter,'confirmed');
 h.document.querySelector('#search').value='Alice';h.document.querySelector('#filters').dispatchEvent(new h.document.defaultView.Event('submit',{cancelable:true}));await tick();assert.equal(h.calls.at(-1).body.event,ids[0]);
 h.run(`openTournament('${ids[1]}','Registrations')`);await tick();assert.match(h.document.querySelector('#records').textContent,/Bob/);assert.equal(h.calls.at(-1).body.query,'');
 h.document.querySelector('#workspace-edit').click();assert.ok(h.document.querySelector('#event-form'));h.document.querySelector('#back').click();await tick();assert.equal(h.document.querySelector('#page-title').textContent,'Event 2');
 h.document.querySelector('#all-tournaments').click();await tick();assert.equal(h.document.querySelector('#page-title').textContent,'Tournaments');assert.equal(h.document.querySelectorAll('[data-open]').length,2);
 h.run("navigate('Registrations')");await tick();assert.ok(h.document.querySelector('#event-filter'));assert.equal(h.calls.at(-1).body.event,'');
 }finally{h.close();}
});
test('late summary cannot replace another event or an open editor',async()=>{
 let release;const pending=new Promise(r=>release=r);let hold=false;
 const h=harness((action,body)=>hold&&action==='tournament_summary'&&body.id===ids[0]?pending:undefined);
 try{await h.run('load()');hold=true;h.run(`openTournament('${ids[0]}')`);h.run(`openTournament('${ids[1]}')`);await tick();release(summary);await tick();assert.equal(h.document.querySelector('#page-title').textContent,'Event 2');assert.equal(h.run('tournamentId'),ids[1]);
 }finally{h.close();}
});
test('late record response cannot overwrite a different tournament',async()=>{
 let release;const pending=new Promise(r=>release=r);const h=harness((action,body)=>action==='admin_list'&&body.event===ids[0]?pending:undefined);
 try{await h.run('load()');h.run(`openTournament('${ids[0]}','Registrations')`);await tick();h.run(`openTournament('${ids[1]}','Registrations')`);await tick();release({total:0,rows:[]});await tick();assert.match(h.document.querySelector('#records').textContent,/Bob/);assert.doesNotMatch(h.document.querySelector('#records').textContent,/Alice/);
 }finally{h.close();}
});
test('failed summary can retry without exposing another event data',async()=>{
 let fail=true;const h=harness(action=>action==='tournament_summary'&&fail?Promise.reject(Error('Offline')):undefined);
 try{await h.run('load()');h.run(`openTournament('${ids[0]}')`);await tick();assert.match(h.document.querySelector('#tournament-content').textContent,/Unable to load/);assert.equal(h.document.querySelectorAll('#stats .stat').length,4);assert.match(h.document.querySelector('#stats').textContent,/—/);fail=false;h.document.querySelector('#retry-workspace').click();await tick();assert.match(h.document.querySelector('#tournament-content').textContent,/Tournament overview/);
 }finally{h.close();}
});
