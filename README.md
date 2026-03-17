# Family Tracker App 🗺️

Ứng dụng Flutter theo dõi vị trí gia đình realtime, sử dụng **Supabase** làm backend.

## ✨ Tính năng

- 🗺️ **Bản đồ realtime** - Hiển thị vị trí tất cả thành viên trên Google Maps
- 👨‍👩‍👧‍👦 **Quản lý gia đình** - Thêm/xóa thành viên qua email
- 📍 **Chia sẻ vị trí** - Bật/tắt chia sẻ vị trí của bản thân
- 🏠 **Vùng an toàn** - Tạo các vùng geofencing (nhà, trường học...)
- 🔔 **Thông báo** - Nhận thông báo khi thành viên vào/ra khỏi vùng an toàn
- 📱 **Cross-platform** - Android & iOS

## 🛠️ Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | Flutter 3.x |
| Backend | Supabase (PostgreSQL + Auth + Realtime) |
| Maps | Google Maps Flutter |
| State Management | Provider |
| CI/CD | GitHub Actions |

## 🚀 Bắt đầu

### Yêu cầu

- Flutter SDK >= 3.0.0
- Supabase account (đã tạo)
- Google Maps API key

### 1. Clone và cài đặt

```bash
git clone https://github.com/thaitieuloi/flutter-tracking-location.git
cd flutter-tracking-location
```

### 2. Setup Supabase Database

1. Mở [Supabase SQL Editor](https://supabase.com/dashboard/project/mftfgumaftkhjwlavpxh/sql)
2. Copy nội dung file `supabase/migrations/001_initial_schema.sql`
3. Chạy SQL để tạo tables, RLS policies, và enable Realtime

### 3. Cấu hình Environment

```bash
cp .env.example .env
```

Cập nhật `.env` với credentials Supabase:

```env
SUPABASE_URL=https://mftfgumaftkhjwlavpxh.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

### 4. Cấu hình Google Maps

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY_HERE"/>
```

### 5. Chạy ứng dụng

```bash
flutter pub get
flutter run
```

### 6. Build APK Release

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## 📂 Cấu trúc Project

```
lib/
├── main.dart                        # Entry point + Supabase init
├── config/
│   └── supabase_config.dart         # Supabase configuration
├── models/
│   └── models.dart                  # Data models (User, Location, SafeZone, Family)
├── services/
│   ├── supabase_service.dart        # Supabase operations + Realtime
│   └── location_service.dart        # GPS/location tracking
├── providers/
│   └── app_provider.dart            # State management (Provider)
└── screens/
    ├── login_screen.dart            # Authentication UI
    └── map_screen.dart              # Main map + family management
```

## 🗄️ Database Schema (Supabase)

```
users/
  - id (UUID, PK, references auth.users)
  - name, email, photo_url
  - family_id, is_location_sharing
  - last_seen, created_at

locations/
  - user_id (UUID, PK, references users)
  - latitude, longitude, accuracy
  - address, timestamp, updated_at

families/
  - id (TEXT, PK)
  - name, created_by, members[]
  - created_at

safe_zones/
  - id (TEXT, PK)
  - name, latitude, longitude
  - radius_meters, family_id
  - notify_on_enter, notify_on_exit
  - created_at
```

## 🔄 CI/CD Pipeline

GitHub Actions tự động chạy khi:

| Trigger | Action |
|---------|--------|
| Push to `main` | Analyze + Build APK |
| Pull Request to `main` | Analyze + Build APK |
| Tag `v*` (e.g. `v1.0.0`) | Analyze + Build APK + Create GitHub Release |

### Setup GitHub Secrets

Vào **Settings → Secrets and variables → Actions**, thêm:

| Secret | Giá trị |
|--------|---------|
| `SUPABASE_URL` | `https://mftfgumaftkhjwlavpxh.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anon key |
| `KEYSTORE_BASE64` | (Optional) Base64 encoded keystore |
| `KEY_ALIAS` | (Optional) Keystore alias |
| `KEY_PASSWORD` | (Optional) Key password |
| `STORE_PASSWORD` | (Optional) Store password |

### Tạo Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

→ GitHub Actions sẽ tự build APK và tạo Release trên GitHub.

## ⚠️ Lưu ý bảo mật

- **KHÔNG** commit file `.env` (đã có trong `.gitignore`)
- **KHÔNG** commit file `key.properties` hoặc keystore
- Sử dụng GitHub Secrets cho CI/CD
- Supabase RLS policies đã được cấu hình trong migration

## 📄 License

MIT License
