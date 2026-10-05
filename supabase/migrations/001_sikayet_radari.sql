-- Şikayet Radarı: veritabanı şeması
-- Supabase SQL Editor'da bir kez çalıştırın (ya da Supabase CLI / MCP ile migration olarak uygulayın).

-- 1) Ekip üyeleri ve roller --------------------------------------------------
create table if not exists public.uyeler (
  email   text primary key,
  rol     text not null default 'editor' check (rol in ('admin','editor','viewer')),
  eklenme timestamptz not null default now()
);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.uyeler where lower(email) = lower(auth.jwt() ->> 'email'));
$$;
create or replace function public.is_editor() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.uyeler where lower(email) = lower(auth.jwt() ->> 'email') and rol in ('admin','editor'));
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.uyeler where lower(email) = lower(auth.jwt() ->> 'email') and rol = 'admin');
$$;
revoke execute on function public.is_member(), public.is_editor(), public.is_admin() from public, anon;
grant  execute on function public.is_member(), public.is_editor(), public.is_admin() to authenticated;

-- 2) Yüklemeler ---------------------------------------------------------------
create table if not exists public.yuklemeler (
  id           uuid primary key default gen_random_uuid(),
  dosya        text not null,
  yukleyen     text,
  yuklenme     timestamptz not null default now(),
  bas          date,
  bit          date,
  toplam       int  not null default 0,
  eklenen      int  not null default 0,
  tekrar_db    int  not null default 0,
  tekrar_dosya int  not null default 0
);

-- 3) Şikayetler ---------------------------------------------------------------
-- hash = tarih + kanal + normalize edilmiş metin. Aynı kayıt ikinci kez eklenemez.
create table if not exists public.sikayetler (
  id             bigint generated always as identity primary key,
  hash           text not null unique,
  tarih          date not null,
  kanal          text not null check (kanal in ('ai','web','mobil','ivr')),
  metin          text not null,
  kaynak_id      text,
  yukleme_id     uuid references public.yuklemeler(id) on delete cascade,
  atanan_alt     text,
  atama_yontemi  text check (atama_yontemi in ('a','u')),
  eklenme        timestamptz not null default now()
);
create index if not exists sikayetler_tarih_idx  on public.sikayetler (tarih);
create index if not exists sikayetler_yukleme_idx on public.sikayetler (yukleme_id);

-- 4) Ayarlar (kategori listesi) -----------------------------------------------
create table if not exists public.ayarlar (
  anahtar     text primary key,
  deger       jsonb not null,
  guncelleme  timestamptz not null default now(),
  guncelleyen text
);

-- 5) Satır düzeyi güvenlik ----------------------------------------------------
alter table public.uyeler     enable row level security;
alter table public.yuklemeler enable row level security;
alter table public.sikayetler enable row level security;
alter table public.ayarlar    enable row level security;

create policy uyeler_oku     on public.uyeler     for select to authenticated using (public.is_member());
create policy uyeler_yonet   on public.uyeler     for all    to authenticated using (public.is_admin()) with check (public.is_admin());

create policy yukleme_oku    on public.yuklemeler for select to authenticated using (public.is_member());
create policy yukleme_ekle   on public.yuklemeler for insert to authenticated with check (public.is_editor());
create policy yukleme_guncel on public.yuklemeler for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy yukleme_sil    on public.yuklemeler for delete to authenticated using (public.is_editor());

create policy sikayet_oku    on public.sikayetler for select to authenticated using (public.is_member());
create policy sikayet_ekle   on public.sikayetler for insert to authenticated with check (public.is_editor());
create policy sikayet_guncel on public.sikayetler for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy sikayet_sil    on public.sikayetler for delete to authenticated using (public.is_editor());

create policy ayar_oku       on public.ayarlar    for select to authenticated using (public.is_member());
create policy ayar_ekle      on public.ayarlar    for insert to authenticated with check (public.is_editor());
create policy ayar_guncel    on public.ayarlar    for update to authenticated using (public.is_editor()) with check (public.is_editor());

-- 6) Canlı güncelleme (yükleme ve kategori değişiklikleri ekipte anında görünür)
alter publication supabase_realtime add table public.yuklemeler, public.ayarlar;

-- 7) Başlangıç kategori listesi ------------------------------------------------
insert into public.ayarlar (anahtar, deger, guncelleyen)
values ('taksonomi', $json${"cats": [{"id": "dd", "name": "Diğer Destek", "subs": [{"id": "dd_belge", "name": "Belge, Ücret & Bildirim", "kw": ["belge", "dekont", "makbuz", "ücret", "masraf", "komisyon", "kesinti", "bildirim", "e-posta", "mail", "bilgilendirme", "sözleşme", "hesap cüzdanı", "vergi"]}, {"id": "dd_diger", "name": "Diğer", "kw": ["destek", "müşteri hizmet", "temsilci", "ulaşamıyorum", "ulaşılamıyor", "geri dönüş", "cevap verilmedi", "yanıt alamadım"]}]}, {"id": "fby", "name": "Faiz, Birikim ve Yatırım", "subs": [{"id": "fby_diger", "name": "Diğer", "kw": ["birikim", "getiri", "kumbara", "hedef birikim"]}, {"id": "fby_doviz", "name": "Döviz, Altın & Yatırım", "kw": ["döviz", "dolar", "euro", "avro", "sterlin", "usd", "eur", "altın", "gram altın", "kur", "yatırım", "fon", "hisse", "borsa"]}, {"id": "fby_faiz", "name": "Günlük Faiz ve Vadeli Hesap", "kw": ["faiz", "günlük faiz", "vadeli", "vade", "mevduat", "faiz oranı", "stopaj"]}]}, {"id": "gd", "name": "Giriş ve Doğrulama", "subs": [{"id": "gd_diger", "name": "Diğer", "kw": ["doğrulama", "doğrulayamıyorum", "onaylanmıyor"]}, {"id": "gd_kimlik", "name": "Kimlik, NFC & Yüz Doğrulama", "kw": ["kimlik", "nfc", "yüz doğrulama", "yüz tanıma", "yüzümü", "selfie", "çip", "kimlik kartı", "canlılık", "görüntülü görüşme", "video görüşme"]}, {"id": "gd_sim", "name": "SIM Blokesi & Cihaz Değişikliği", "kw": ["sim", "sim kart", "sim blokesi", "sim bloke", "cihaz değişikliği", "cihaz değiştir", "yeni telefon", "telefon değiştir", "telefonumu değiştir", "hat değiş", "operatör"]}, {"id": "gd_sms", "name": "SMS & Doğrulama Kodu", "kw": ["sms", "doğrulama kodu", "onay kodu", "otp", "tek kullanımlık", "kod gelmiyor", "kod gelmedi", "mesaj gelmiyor"]}, {"id": "gd_sifre", "name": "Şifre, Giriş & Uygulama", "kw": ["şifre", "parola", "giriş yapamıyorum", "giriş yapamadım", "giremiyorum", "uygulama açılmıyor", "uygulama hata", "uygulama çöküyor", "donuyor", "oturum", "login", "uygulamaya"]}]}, {"id": "hs", "name": "Hesap", "subs": [{"id": "hs_diger", "name": "Diğer", "kw": ["hesap", "hesabım"]}, {"id": "hs_guncel", "name": "Hesap Güncellemesi", "kw": ["adres", "güncelle", "bilgi güncelle", "bilgilerimi güncelle", "adres değiş", "adresimi", "numara değiş", "numaramı değiştir", "e-posta değiş", "iletişim bilgi", "isim değiş", "soyadı", "meslek bilgi", "gelir bilgi"]}, {"id": "hs_kapat", "name": "Hesap Kapatma", "kw": ["hesap kapat", "hesabımı kapat", "hesabı kapat", "hesabımı sil", "hesap sil", "üyelik iptal", "üyeliğimi iptal", "hesap kapama"]}, {"id": "hs_kullan", "name": "Hesap Kullanımı", "kw": ["hesap bloke", "hesabım bloke", "hesabıma bloke", "kısıtlama", "kısıtlandı", "hesap dondur", "donduruldu", "bakiye", "hesap aç", "iban", "hesap hareket", "hesap limiti"]}]}, {"id": "kg", "name": "Kampanya ve GetirPara", "subs": [{"id": "kg_diger", "name": "Diğer", "kw": ["puan", "ödül", "hediye"]}, {"id": "kg_gp", "name": "GetirPara", "kw": ["getirpara", "getir para", "getir parası"]}, {"id": "kg_kamp", "name": "Kampanya", "kw": ["kampanya", "indirim", "promosyon", "kupon", "fırsat", "davet", "referans", "çekiliş", "cashback", "para iadesi kampanya"]}]}, {"id": "kt", "name": "Kart", "subs": [{"id": "kt_diger", "name": "Diğer", "kw": ["kart", "kartım"]}, {"id": "kt_iade", "name": "İade & Provizyon", "kw": ["iade", "provizyon", "bloke tutar", "para iadesi", "çift çekim", "iki kez çekildi", "iki defa çekildi", "harcama itiraz", "itiraz", "chargeback"]}, {"id": "kt_basvuru", "name": "Kart Başvurusu ve Kullanımı", "kw": ["kart başvur", "kart teslim", "kartım gelmedi", "kart gelmedi", "kargo", "kurye", "fiziksel kart", "sanal kart", "kart aktif", "kartı aktif", "temassız", "atm", "pos"]}, {"id": "kt_borc", "name": "Kart Borcu, Ekstre & Fatura", "kw": ["kart borcu", "kart borcum", "ekstre", "hesap kesim", "asgari", "son ödeme", "fatura", "kart ödemesi", "gecikme faizi"]}, {"id": "kt_islem", "name": "Kart İşlemleri", "kw": ["kart limit", "kart şifre", "kartım bloke", "kart bloke", "kart iptal", "kartımı iptal", "kartı kapat", "kartım çalındı", "kaybettim", "yurt dışı", "internet alışveriş", "3d secure", "işlem reddedildi", "ödeme reddedildi", "harcama yapamıyorum"]}]}, {"id": "kr", "name": "Kredi", "subs": [{"id": "kr_diger", "name": "Diğer", "kw": ["kredi"]}, {"id": "kr_basvuru", "name": "Kredi Başvurusu", "kw": ["kredi başvur", "başvurum", "kredi limiti", "kredi notu", "findeks", "ihtiyaç kredisi", "kredi teklif", "kredi onay"]}, {"id": "kr_kapat", "name": "Kredi Kapatma & Yapılandırma", "kw": ["kredi kapat", "kredimi kapat", "erken kapama", "erken ödeme", "yapılandırma", "kapama tutarı", "ara ödeme"]}, {"id": "kr_taksit", "name": "Kredi Taksiti", "kw": ["taksit", "kredi taksit", "taksidim", "ödeme planı", "otomatik ödeme", "gecikme", "icra"]}]}, {"id": "pt", "name": "Para Transferleri", "subs": [{"id": "pt_diger", "name": "Diğer", "kw": ["transfer", "para transferi", "gelen para", "para gelmedi", "hesabıma geçmedi"]}, {"id": "pt_giden", "name": "Giden Para Transferi", "kw": ["para gönder", "gönderdiğim para", "gönderdim", "gönderim", "eft", "havale", "fast", "alıcıya ulaşmadı", "alıcıya geçmedi", "yanlış iban", "karşı tarafa geçmedi"]}]}]}$json$::jsonb, 'kurulum')
on conflict (anahtar) do nothing;

-- 8) İLK YÖNETİCİ: kendi e-postanı yaz ve çalıştır (Authentication > Users'ta da aynı e-postayla kullanıcı oluştur)
-- insert into public.uyeler (email, rol) values ('sen@ornek.com', 'admin');
