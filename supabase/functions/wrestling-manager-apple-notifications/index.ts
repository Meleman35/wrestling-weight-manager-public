import pg from 'npm:pg@8.16.3';
import {createNotificationHost} from '../../../billing-candidate/notification-host.mjs';
// Custom authentication: signed Apple payloads and a private scheduler token.
// User purchase commands are not routed by this Edge Function.
Deno.serve(createNotificationHost({Pool:pg.Pool,readSecret:(name:string)=>Deno.env.get(name)}));
