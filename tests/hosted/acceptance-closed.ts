// Hosted acceptance completed and fixtures cleaned; runner disabled.
Deno.serve(() => Response.json({error:'acceptance_closed'}, {status:410,headers:{'Cache-Control':'no-store'}}));
