import {NextResponse} from 'next/server';
import {supabase,saveSession,sameOrigin} from '../../../../lib/supabase';
export const runtime='nodejs';
export async function POST(req:Request){
 if(!sameOrigin(req))return new Response('Origem inválida',{status:403});
 try{const form=await req.formData();const email=String(form.get('email')||'').trim(),password=String(form.get('password')||'');
 if(!email||email.length>254||!password||password.length>256)return NextResponse.redirect(new URL('/login?error=credentials',req.url),303);
 const {response,body}=await supabase('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email,password})});
 if(!response.ok||!body.access_token||!body.refresh_token)return NextResponse.redirect(new URL('/login?error=credentials',req.url),303);
 await saveSession(body);return NextResponse.redirect(new URL('/',req.url),303);
 }catch{return NextResponse.redirect(new URL('/login?error=network',req.url),303)}
}
