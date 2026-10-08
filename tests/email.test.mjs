import test from 'node:test';
import assert from 'node:assert/strict';
import {emailConfig,checkRecipient} from '../supabase/functions/drvn-api/email.mjs';
const env = values => key => values[key] || '';
test('initial sender is recorded but missing credentials do not enable delivery', () => {
 const c=emailConfig(env({}));assert.equal(c.user,'xdqwerts@gmail.com');assert.equal(c.configured,false);assert.throws(()=>checkRecipient(c,c.user),/credentials/);
});
test('test mode only permits explicitly configured inboxes',()=>{
 const c=emailConfig(env({GMAIL_APP_PASSWORD:'test-fixture',EMAIL_TEST_RECIPIENTS:'one@example.invalid,two@example.invalid'}));
 assert.doesNotThrow(()=>checkRecipient(c,'ONE@example.invalid'));assert.throws(()=>checkRecipient(c,'player@example.invalid'),/Test mode/);
});
test('production delivery requires explicit mode and valid provider configuration',()=>{
 const c=emailConfig(env({EMAIL_MODE:'production',EMAIL_PROVIDER:'resend',RESEND_API_KEY:'fixture',EMAIL_FROM:'club@example.invalid'}));assert.doesNotThrow(()=>checkRecipient(c,'player@example.invalid'));
});
