export const SUPABASE='https://nrxlfjtzdwkdvwbmrphx.supabase.co';
export const PUBLIC_KEY='sb_publishable_6UZHMr8hoRVcye2QrbkmIQ_BQXJr7yT';
export const API=SUPABASE+'/functions/v1/drvn-api';
export const $=(s,r=document)=>r.querySelector(s);
export const escape=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const peso=v=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(v/100);
export const date=v=>new Intl.DateTimeFormat('en-PH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Manila'}).format(new Date(v));
export const label=v=>String(v||'').replaceAll('_',' ');
let refreshing;
async function responseJSON(response){try{return await response.json();}catch{throw Error('The server returned an unexpected response. Please try again.');}}
async function requestJSON(url,options){let response;try{response=await fetch(url,{...options,signal:AbortSignal.timeout(30000)});}catch(error){throw Error(error.name==='TimeoutError'?'The request took too long. Check your connection and try again.':'Unable to reach the server. Check your connection and try again.');}return {response,data:await responseJSON(response)};}
async function sessionToken(){let session;try{session=JSON.parse(sessionStorage.getItem('drvn-session')||'null');}catch{sessionStorage.removeItem('drvn-session');}if(!session?.access_token||!session?.refresh_token)throw Error('Please sign in again');if(session.expires_at>=Date.now()+60000)return session.access_token;
if(!refreshing)refreshing=(async()=>{const {response,data:s}=await requestJSON(SUPABASE+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:PUBLIC_KEY,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refresh_token})});if(!response.ok){sessionStorage.removeItem('drvn-session');throw Error('Your session expired. Please sign in again.');}if(!sessionStorage.getItem('drvn-session'))throw Error('You have signed out. Please sign in again.');s.expires_at=Date.now()+s.expires_in*1000;sessionStorage.setItem('drvn-session',JSON.stringify(s));return s.access_token;})().finally(()=>{refreshing=undefined;});return refreshing;}
export async function api(action,body={},auth=false){const token=auth?await sessionToken():'';const {response,data}=await requestJSON(API,{method:'POST',headers:{'Content-Type':'application/json',apikey:PUBLIC_KEY,...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify({...body,action})});if(!response.ok)throw Error(data?.error||'Unable to complete this request');return data;}
export async function fileData(file){if(!file)throw Error('Choose a photo');if(file.size>2097152)throw Error('Choose a JPG, PNG or WebP under 2 MB');return {data:await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).split(',')[1]);r.onerror=reject;r.readAsDataURL(file);})};}
export function busy(form,on){form.querySelectorAll('button').forEach(b=>b.disabled=on);}
export function message(text){const el=$('#message');el.textContent=text;el.hidden=!text;}
