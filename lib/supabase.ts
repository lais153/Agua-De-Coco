import 'server-only';
import {cookies} from 'next/headers';

export function configured(){return Boolean(process.env.SUPABASE_URL&&process.env.SUPABASE_ANON_KEY)}
export async function supabase(path:string,options:RequestInit={},token?:string){
  const url=process.env.SUPABASE_URL?.replace(/\/$/,'');
  const key=process.env.SUPABASE_ANON_KEY;
  if(!url||!key)throw Error('Configure SUPABASE_URL e SUPABASE_ANON_KEY na Vercel.');
  const response=await fetch(url+path,{...options,cache:'no-store',headers:{apikey:key,...(token?{Authorization:`Bearer ${token}`} : {}),'Content-Type':'application/json',...options.headers},signal:AbortSignal.timeout(20000)});
  const body=await response.json().catch(()=>({}));
  return {response,body};
}
export async function saveSession(session:{access_token:string;refresh_token:string}){
  const jar=await cookies();const settings={httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax' as const,path:'/',maxAge:60*60*24*14};
  jar.set('realeza-access',session.access_token,settings);jar.set('realeza-refresh',session.refresh_token,settings);
}
export async function clearSession(){const jar=await cookies();jar.delete('realeza-access');jar.delete('realeza-refresh');}
export async function getUser(){
  if(!configured())return null;
  const token=(await cookies()).get('realeza-access')?.value;
  if(!token)return null;
  const {response,body}=await supabase('/auth/v1/user',{},token);
  return response.ok&&body.id?{userId:body.id as string,email:body.email as string,token}:null;
}
export async function refreshSession(){
  const refresh=(await cookies()).get('realeza-refresh')?.value;
  if(!refresh||!configured())return false;
  const {response,body}=await supabase('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:refresh})});
  if(!response.ok||!body.access_token||!body.refresh_token)return false;
  await saveSession(body);return true;
}
export async function apiUser(){let user=await getUser();if(!user&&await refreshSession())user=await getUser();return user;}
export function sameOrigin(req:Request){return req.headers.get('origin')===new URL(req.url).origin;}
