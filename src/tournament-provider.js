/* Adapter boundary: authorization and provider normalization stay on the server.
 * A supported live connector can implement this request contract once approved.
 * IDs in board responses are stable internal IDs, never names or display numbers.
 */
window.WMTournamentProviders={
 manual:{source:'manual',connected:true,request:(client,action,data)=>client.rpc('tournament_request',{p_action:action,p_data:data})},
 usa_bracketing:{source:'usa_bracketing',connected:false,async request(){throw new Error('USA Bracketing access and documentation are pending. No live connection is configured.');}}
};
