import {NextResponse} from 'next/server';
import {clearSession,getUser,supabase,sameOrigin} from '../../../../lib/supabase';
export async function POST(req:Request){if(!sameOrigin(req))return new Response('Origem inválida',{status:403});try{const user=await getUser();if(user)await supabase('/auth/v1/logout?scope=local',{method:'POST'},user.token);}catch{}await clearSession();return NextResponse.redirect(new URL('/login',req.url),303);}
