// Shared, presentation-only workspace helpers. No changes to stored event data.
export const workspaceTabs=['Overview','Players','Categories','Registrations','Payments','Photos','Reports'];
export function categoryRows(summary,{escape:e,peso,pill}){
 return summary.categories.map(c=>`<tr><td><strong>${e(c.name)}</strong><small>${c.active?'Open category':'Disabled category'}</small></td><td>${c.unit==='team'?'Team of two':'Individual'}<small>${peso(c.fee_cents)} per entry</small></td><td>${c.occupied} / ${c.capacity}<small>${Math.max(0,c.capacity-c.occupied)} unoccupied slots</small></td><td>${c.confirmed}<small>${c.confirmed_players} player places</small></td><td>${c.waitlisted}</td></tr>`);
}
export function workspaceMetrics(s,peso){return [
 ['Confirmed player places',s.confirmed_players,`${s.confirmed} confirmed entries · teams count as two`],
 ['Total registrations',s.registrations,`${s.waitlisted} waitlisted entries`],
 ['Pending payments',s.pending,'Submitted proofs awaiting review'],
 ['Verified collections',peso(s.collections),'Excludes recorded refunds']
 ];}
