# Şikayet Radarı — kurulum

AI Asistan, Web Form, Mobil Form ve Çağrı Merkezi (IVR) şikayetlerini Excel'den yükleyip sınıflandıran, tekrarları ayıklayan ve tarih/kanal bazında trend gösteren ekip paneli.

```
public/index.html                     Uygulamanın kendisi (tek sayfa)
netlify/functions/classify.mjs        AI sınıflandırma uç noktası (/api/classify) — Claude API anahtarı burada, sunucuda kalır
scripts/write-config.mjs              Netlify build adımı: Supabase bağlantı bilgisini public/config.js'e yazar
supabase/migrations/001_sikayet_radari.sql   Veritabanı tabloları, yetki kuralları, başlangıç kategori listesi
netlify.toml                          Netlify ayarları
```

## Mimari

| Parça | Nerede | Not |
|---|---|---|
| Site | Netlify (statik) | Giriş ekranı, panel, Excel okuma tarayıcıda |
| Veri | Supabase (Postgres) | `sikayetler`, `yuklemeler`, `ayarlar`, `uyeler` tabloları; satır düzeyi güvenlik açık |
| Giriş | Supabase Auth (e-posta + şifre) | Kayıt kapalı, kullanıcıyı yönetici ekler |
| AI | Netlify Function → Claude API | Yalnızca `editor`/`admin` rolündekiler çağırabilir |

Tekrar kontrolü veritabanında yapılır: her kaydın `hash` değeri (tarih + kanal + normalize edilmiş metin) benzersizdir, aynı kayıt ikinci kez eklenemez.

## 1. Supabase

1. supabase.com'da yeni proje aç. **Bölge olarak Frankfurt (eu-central-1)** seç.
2. **SQL Editor** → `supabase/migrations/001_sikayet_radari.sql` dosyasının içeriğini yapıştırıp çalıştır.
3. **Authentication → Sign In / Providers**: "Allow new users to sign up" seçeneğini **kapat** (herkes kendi kendine hesap açamasın).
4. **Authentication → Users → Add user → Create new user**: kendi e-postan ve şifrenle kullanıcı oluştur, "Auto Confirm User" işaretli olsun.
5. SQL Editor'da kendini yönetici yap:
   ```sql
   insert into public.uyeler (email, rol) values ('senin@e-postan.com', 'admin');
   ```
6. **Project Settings → API**: `Project URL` ve `anon` / `publishable` anahtarını not et.

## 2. Claude API anahtarı

console.anthropic.com → API Keys → yeni anahtar. Varsayılan model `claude-haiku-4-5-20251001` (hızlı ve ucuz). Farklı model için `ANTHROPIC_MODEL` ortam değişkenini kullan.

Kabaca maliyet: 1.000 şikayeti AI ile sınıflandırmak ~0,20 $ civarındadır (yalnızca kurallarla eşleşmeyenler AI'a gider).

## 3. Netlify

Fonksiyon içerdiği için Netlify Drop (sürükle-bırak) yerine Git ya da CLI ile yayınla:

- **Git ile:** Bu klasörü bir GitHub deposuna koy → Netlify → Add new site → Import from Git. Build ayarları `netlify.toml`'dan okunur.
- **CLI ile:** `npx netlify-cli deploy --prod` (klasörün içinde).

**Site configuration → Environment variables** bölümüne ekle, sonra yeniden deploy et:

| Değişken | Değer |
|---|---|
| `SUPABASE_URL` | Supabase Project URL |
| `SUPABASE_ANON_KEY` | Supabase anon / publishable anahtar |
| `ANTHROPIC_API_KEY` | Claude API anahtarı (yalnızca sunucuda kullanılır) |
| `ANTHROPIC_MODEL` | (isteğe bağlı) |

Son olarak Supabase → **Authentication → URL Configuration → Site URL** alanına Netlify adresini yaz.

## 4. Ekibi ekleme

Her ekip arkadaşı için:

1. Supabase → Authentication → Users → **Add user** (e-posta + geçici şifre, Auto Confirm). Şifreyi kişiye ilet; giriş yaptıktan sonra sağ üstteki menüden değiştirebilir.
2. SQL Editor:
   ```sql
   insert into public.uyeler (email, rol) values ('ad.soyad@sirket.com', 'editor');
   ```

Roller: `admin` (üye yönetimi dahil her şey), `editor` (yükleme, sınıflandırma, kategori düzenleme), `viewer` (yalnızca görüntüleme). Erişimi kaldırmak için `delete from public.uyeler where email = '...'`.

## Veri güvenliği notu

Şikayet metinleri müşteri verisi içerebilir. Kişisel veri Supabase'e (seçtiğin bölge) ve AI sınıflandırma sırasında Anthropic'e gönderilir. Gerçek veriyi yüklemeden önce şirketin bilgi güvenliği / KVKK ekibinin onayını almanı öneririm. Gerekirse yüklemeden önce müşteri adı, TCKN, telefon gibi alanları Excel'den çıkar; panel yalnızca tarih, kanal ve şikayet metnine ihtiyaç duyar.
