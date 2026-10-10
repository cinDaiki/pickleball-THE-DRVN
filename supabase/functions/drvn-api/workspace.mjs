// The caller has already authenticated the organizer. Context is optional for
// compatibility with the existing global admin screens.
export async function assertTournamentScope(action,body,one,uuid){
 if(!body.tournament_id||!['entry_action','review','receipt'].includes(action))return;
 const eventId=uuid(body.tournament_id),id=uuid(body.id);
 const registrationId=action==='entry_action'?id:(await one('payments',`id=eq.${id}`)).registration_id;
 const record=await one('registrations',`id=eq.${registrationId}`);
 const category=await one('categories',`id=eq.${record.category_id}`);
 if(category.tournament_id!==eventId)throw Error('This record does not belong to the selected tournament');
}
