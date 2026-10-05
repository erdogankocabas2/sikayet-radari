// Netlify build adımı: Supabase bağlantı bilgisini tarayıcıya verilecek config.js dosyasına yazar.
// Anon anahtar herkese açık olacak şekilde tasarlanmıştır; verileri satır düzeyi güvenlik (RLS) korur.
import { writeFileSync } from 'node:fs';
const url = process.env.SUPABASE_URL || '', key = process.env.SUPABASE_ANON_KEY || '';
if (!url || !key) console.warn('UYARI: SUPABASE_URL veya SUPABASE_ANON_KEY tanımlı değil; site giriş ekranında yapılandırma uyarısı gösterecek.');
writeFileSync('public/config.js', `window.RADAR_CONFIG = ${JSON.stringify({ supabaseUrl: url, supabaseAnonKey: key })};\n`);
console.log('public/config.js yazıldı.');
