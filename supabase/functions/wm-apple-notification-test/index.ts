// Completed operator diagnostic. Reopen only for a bounded reviewed test.
Deno.serve(()=>Response.json({error:'diagnostic_closed'},{status:410,headers:{'Cache-Control':'no-store'}}));
