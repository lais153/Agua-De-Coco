import {NextResponse} from 'next/server';
import {refreshSession,clearSession} from '../../../../lib/supabase';
export async function GET(req:Request){try{if(await refreshSession())return NextResponse.redirect(new URL('/',req.url));}catch{}await clearSession();return NextResponse.redirect(new URL('/login',req.url));}
