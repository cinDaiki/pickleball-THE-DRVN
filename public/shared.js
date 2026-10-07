export const SUPABASE='https://nrxlfjtzdwkdvwbmrphx.supabase.co';
export const PUBLIC_KEY='sb_publishable_6UZHMr8hoRVcye2QrbkmIQ_BQXJr7yT';
export const API=SUPABASE+'/functions/v1/drvn-api';
export const $=(s,r=document)=>r.querySelector(s);
export const escape=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const peso=v=>new Intl.NumberFormat('en-PH',{style:'currency',currency:'PHP'}).format(v/100);
export const date=v=>new Intl.DateTimeFormat('en-PH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Manila'}).format(new Date(v));
export const label=v=>String(v||'').replaceAll('_',' ');
export async function api(action,body={},auth=false){let token='';if(auth){const session=JSON.parse(sessionStorage.getItem('drvn-session')||'null');if(!session)throw Error('Please sign in again');if(session.expires_at<Date.now()+60000){const r=await fetch(SUPABASE+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:PUBLIC_KEY,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:session.refresh_token})});const s=await r.json();if(!r.ok){sessionStorage.removeItem('drvn-session');location.assign('/admin/login');throw Error('Session expired');}s.expires_at=Date.now()+s.expires_in*1000;sessionStorage.setItem('drvn-session',JSON.stringify(s));token=s.access_token;}else token=session.access_token;}
const r=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json',apikey:PUBLIC_KEY,...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify({action,...body})});const data=await r.json();if(!r.ok)throw Error(data.error||'Unable to complete this request');return data;}
export async function fileData(file){if(!file)throw Error('Choose a photo');if(file.size>2097152)throw Error('Choose a JPG, PNG or WebP under 2 MB');return {data:await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).split(',')[1]);r.onerror=reject;r.readAsDataURL(file);})};}
export function busy(form,on){form.querySelectorAll('button').forEach(b=>b.disabled=on);}
export function message(text){const el=$('#message');el.textContent=text;el.hidden=!text;}
