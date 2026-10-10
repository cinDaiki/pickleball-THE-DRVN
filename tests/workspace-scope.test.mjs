import test from 'node:test';
import assert from 'node:assert/strict';
import {assertTournamentScope} from '../supabase/functions/drvn-api/workspace.mjs';
import {uuid} from '../supabase/functions/drvn-api/core.mjs';
const a='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',b='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const one=async(table)=>({payments:{registration_id:a},registrations:{category_id:a},categories:{tournament_id:a}}[table]);
test('workspace rejects wrong-event entry actions, reviews and private receipts',async()=>{for(const action of ['entry_action','review','receipt']){await assert.rejects(assertTournamentScope(action,{id:a,tournament_id:b},one,uuid),/selected tournament/);await assertTournamentScope(action,{id:a,tournament_id:a},one,uuid);}});
test('global workflows remain compatible and malformed context is rejected',async()=>{await assertTournamentScope('review',{id:a},()=>{throw Error('Unexpected lookup');},uuid);await assert.rejects(assertTournamentScope('review',{id:a,tournament_id:'invalid'},one,uuid));});
