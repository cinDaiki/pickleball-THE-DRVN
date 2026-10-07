export const occupiedStatuses=['awaiting_payment','under_review','confirmed','correction_requested'];
export function money(value){const n=Number(value);if(!Number.isSafeInteger(n)||n<0||n>100000000)throw Error('Invalid amount');return n;}
export function required(value,max=200){if(typeof value!=='string'||!value.trim()||value.length>max)throw Error('Check the required fields');return value.trim();}
export function uuid(v){if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v||''))throw Error('Invalid identifier');return v;}
export function reference(v){const s=required(v,30).replace(/[\s-]/g,'');if(!/^\d{10,20}$/.test(s))throw Error('Enter the numeric GCash transaction reference');return s;}
export function imageType(b){if(b.length<12)throw Error('Invalid image');if(b[0]===255&&b[1]===216&&b[2]===255)return ['image/jpeg','jpg'];if([137,80,78,71,13,10,26,10].every((v,i)=>b[i]===v))return ['image/png','png'];if(String.fromCharCode(...b.slice(0,4))==='RIFF'&&String.fromCharCode(...b.slice(8,12))==='WEBP')return ['image/webp','webp'];throw Error('Upload a JPG, PNG or WebP image');}
export function csv(rows){return rows.map(r=>r.map(v=>'"'+String(v??'').replace(/^[=+@\-\t\r]/,"'$&").replaceAll('"','""')+'"').join(',')).join('\r\n');}
export function effectiveStatus(r,now=Date.now()){return r.status==='awaiting_payment'&&Date.parse(r.expires_at)<now?'expired':r.status;}
export async function hash(v){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(v)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export async function tokenFor(id,secret){const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(id)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
