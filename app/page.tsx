import Caixa from './caixa';
import {getUser,configured} from '../lib/supabase';
import {cookies} from 'next/headers';
import {redirect} from 'next/navigation';
export const dynamic='force-dynamic';
export default async function Page(){if(!configured())redirect('/login');const user=await getUser();if(!user){if((await cookies()).get('realeza-refresh'))redirect('/api/auth/refresh');redirect('/login');}return <Caixa email={user.email}/>;}
