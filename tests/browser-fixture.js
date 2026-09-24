
  const F=window.fixture={session:null,confirmation:false,signupError:null,signupDelay:0,matchRows:[],matchError:null,matchDelay:0,calls:[],writes:[],signupCalls:[],rpcError:null,staffRows:[],staffSaves:[],failStaff:false,staffDelay:0,notificationCalls:0};
  const clone=x=>JSON.parse(JSON.stringify(x));
  const channel={on(){return this;},subscribe(){return this;},unsubscribe(){},send:async()=>({}),track:async()=>({})};
  const table=name=>{const q={select(){return this;},eq(){return this;},in(){return this;},order(){return this;},limit(){return this;},is(){return this;},maybeSingle:async()=>({data:name==='profiles'?{id:F.session?.user.id,display_name:'Test Adult',ui_preferences:{}}:null,error:null}),then(resolve){resolve({data:name==='staff_personal_weights'?F.staffRows:[],error:null});}};return q;};
  window.supabase={createClient:()=>({
   auth:{getSession:async()=>({data:{session:F.session}}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),
    signUp:async input=>{F.signupCalls.push(clone(input));if(F.signupDelay)await new Promise(r=>setTimeout(r,F.signupDelay));if(F.signupError)return {error:{message:F.signupError}};const user={id:'new-user',email:input.email,user_metadata:input.options.data};F.session=F.confirmation?null:{user};return {data:{session:F.session,user},error:null};},
    signOut:async()=>{F.session=null;return {error:null};}},
   from:table,channel:()=>channel,removeChannel(){},realtime:{setAuth(){}},storage:{from:()=>({getPublicUrl:()=>({data:{publicUrl:''}})})},
   rpc:(name,args)=>{const promise=(async()=>{
    F.calls.push({name,args:clone(args||{})});
    if(name==='organization_governance')return window.governanceRpc(args.p_request);
    if(name==='get_operations'){
      const orgs=[{id:'org-a',name:'Example School District',organization_type:'school_district'},{id:'org-b',name:'Example State Association',organization_type:'association'}];
      if(args.p_request.action==='context')return {data:orgs,error:null};
      if(args.p_request.action==='hub')return {data:{organization_id:args.p_request.organization_id,organizations:orgs,divisions:[],teams:[],team_events:[],records:[],roles:[],family:[],signatures:[],user_id:'coach',admin:true,president:true,capabilities:[{division_id:null,event:true,records:true}]},error:null};
    }
    if(name==='team_people_request'){
      const result=clone({people:F.people||[],organization_admin:false});
      if(args.p_action==='list'){if(F.peopleDelay)await new Promise(r=>setTimeout(r,F.peopleDelay));return {data:result,error:F.peopleError?{message:F.peopleError}:null};}
      F.writes.push({name,args:clone(args)});if(F.peopleSaveDelay)await new Promise(r=>setTimeout(r,F.peopleSaveDelay));return {data:{user_id:args.p_data.user_id},error:F.peopleError?{message:F.peopleError}:null};
    }
    if(name==='create_adult_staff_invitation'){F.writes.push({name,args:clone(args)});return {data:{invitation_token:'WMM-TEST-PRIVATE'},error:null};}
    if(name==='record_staff_scale_weight'){F.staffSaves.push(clone(args));if(F.staffDelay)await new Promise(r=>setTimeout(r,F.staffDelay));if(!F.staffRows.some(r=>r.check_id===args.p_check_id))F.staffRows.push({check_id:args.p_check_id,weight_lbs:args.p_weight_lbs,practice_phase:args.p_practice_phase,captured_at:new Date().toISOString()});return {data:F.staffRows.find(r=>r.check_id===args.p_check_id),error:F.failStaff?{message:'Simulated lost response'}:null};}
    if(name==='preview_team_join_code')return {data:[{team_id:'team-a',team_name:'Test Wrestling',organization_name:'Test Club'}],error:null};
    if(name==='find_claimable_team_profiles'){const rows=clone(F.matchRows),error=F.matchError;if(F.matchDelay)await new Promise(r=>setTimeout(r,F.matchDelay));return {data:rows,error:error?{message:error}:null};}
    if(['submit_team_profile_claim','submit_team_join_request_v3','submit_parent_child_request_v2','accept_manager_invitation','accept_guardian_invitation','accept_athlete_claim_invitation','bootstrap_wrestling_organization'].includes(name)){F.writes.push({name,args:clone(args)});return {data:'team-a',error:F.rpcError?{message:F.rpcError}:null};}
    if(name==='get_my_team_login')return {data:null,error:null};
    return {data:[],error:null};
   })();promise.abortSignal=()=>promise;return promise;}
  })};