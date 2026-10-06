import pg from 'npm:pg@8.16.3';
import {createBillingDatabaseReadiness} from './database-check.mjs';
// Keep gateway JWT verification enabled. No customer data or mutations.
Deno.serve(createBillingDatabaseReadiness({Pool:pg.Pool,readSecret:(name:string)=>Deno.env.get(name)}));
