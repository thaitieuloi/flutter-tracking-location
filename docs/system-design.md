# Together Home — Tài Liệu Thiết Kế Hệ Thống

> **Stack công nghệ:** Flutter · Supabase · Leaflet Maps (OpenStreetMap)
> **Phiên bản tài liệu:** 2.0 — Tháng 3/2026
> **Nguyên tắc thiết kế:** Đơn giản trước — Nâng cao sau

---

## Mục Lục

1. [Tổng Quan Hệ Thống](#1-tổng-quan-hệ-thống)
2. [Phân Tích Tính Năng](#2-phân-tích-tính-năng)
3. [Kiến Trúc Hệ Thống](#3-kiến-trúc-hệ-thống)
4. [Thiết Kế Database](#4-thiết-kế-database)
5. [Edge Functions](#5-edge-functions)
6. [Thiết Kế Flutter App](#6-thiết-kế-flutter-app)
7. [Supabase Configuration](#7-supabase-configuration)
8. [Security & Privacy](#8-security--privacy)
9. [Lộ Trình Phát Triển](#9-lộ-trình-phát-triển)

---

## 1. Tổng Quan Hệ Thống

### 1.1 Mô Tả Sản Phẩm

**Together Home** là ứng dụng **chia sẻ vị trí thời gian thực** dành cho gia đình. Các thành viên trong một "Family" (gia đình) có thể theo dõi vị trí của nhau, nhận thông báo khi có người đến/rời vùng an toàn, và gửi tín hiệu SOS khi khẩn cấp.

### 1.2 Đối Tượng Sử Dụng

| Đối tượng | Nhu cầu chính |
|-----------|---------------|
| Phụ huynh | Theo dõi vị trí con cái, nhận cảnh báo khi con đến/rời trường |
| Gia đình | Biết vị trí nhau, phối hợp di chuyển |
| Người cao tuổi | Được người thân theo dõi, gửi tín hiệu SOS |

### 1.3 Nguyên Tắc Thiết Kế

- **Đơn giản trước:** Đăng ký → tạo/join family → dùng ngay. Không cần kích hoạt, xác minh phức tạp.
- **Trải nghiệm tốt:** Giảm thiểu số bước để người dùng bắt đầu sử dụng.
- **Nâng cao sau:** Các tính năng phức tạp (Premium, Analytics, AI...) để các sprint sau.

---

## 2. Phân Tích Tính Năng

### 2.1 Tính Năng Hiện Tại (Đã Triển Khai)

#### 2.1.1 Xác Thực & Tài Khoản

- Đăng ký bằng email/password — **đơn giản**, đăng ký xong dùng ngay
- Hỗ trợ truyền `invite_code` khi đăng ký → tự động join family
- Tự động tạo profile khi đăng ký (trigger `handle_new_user()`)
- Quản lý hồ sơ: display_name, avatar

#### 2.1.2 Family Management (Quản Lý Gia Đình)

- Tạo Family với tên tùy chỉnh
- Tự động tạo invite_code (8 ký tự, unique)
- Mời thành viên qua invite code
- Phân quyền: `admin` / `member`
- Admin có thể xóa thành viên khỏi family
- Thành viên có thể tự rời family

#### 2.1.3 Real-Time Location Tracking

- Gửi vị trí GPS định kỳ lên Supabase
- Thuật toán thông minh: chỉ gửi khi di chuyển đáng kể (> 50m) hoặc hết thời gian tối đa
- Bảng `latest_locations` lưu vị trí mới nhất mỗi user (upsert)
- Bảng `user_locations` lưu lịch sử vị trí
- Realtime subscription qua Supabase Realtime
- Hiển thị trạng thái: `is_moving`, `battery_level`, `speed`, `heading`
- Hiển thị "last seen" cho user offline

#### 2.1.4 Bản Đồ (Leaflet / Google Maps)

- Hiển thị vị trí tất cả thành viên family trên bản đồ
- Custom markers với avatar, tên, trạng thái
- Hỗ trợ cả Leaflet (OpenStreetMap) và Google Maps qua adapter pattern
- Center vào vị trí của mình

#### 2.1.5 Geofencing (Vùng An Toàn)

- Tạo geofence với tên, vị trí, bán kính (mặc định 500m)
- Edge Function `check-geofence` kiểm tra enter/exit tự động
- Ghi lại `geofence_events` (enter/exit)
- Gửi notification cho thành viên family khi có sự kiện
- Tùy chỉnh notification per-user qua `geofence_notification_prefs`

#### 2.1.6 SOS / Cảnh Báo Khẩn Cấp

- Gửi SOS kèm vị trí hiện tại
- Edge Function `send-sos-notification` thông báo cho toàn bộ family
- Lưu SOS vào bảng `sos_alerts`

#### 2.1.7 Messaging (Chat Nội Bộ)

- Chat trong family (text)
- Hỗ trợ gửi hình ảnh (Storage bucket `chat-images`)
- Chia sẻ vị trí qua chat (`location_lat`, `location_lng`)
- Realtime subscription cho messages

#### 2.1.8 Notifications

- In-app notifications cho geofence events, SOS, battery thấp, inactivity
- Edge Function `send-battery-alert` cảnh báo pin < 20%
- Edge Function `check-inactivity` phát hiện user không hoạt động > 4h
- Mark as read, delete notification

#### 2.1.9 Location History

- Lưu lịch sử vị trí trong `user_locations`
- Auto cleanup sau 30 ngày (function `cleanup_old_locations()`)
- Màn hình xem lại hành trình

#### 2.1.10 Live Location Sessions

- Tạo session chia sẻ vị trí trực tiếp với thời hạn
- Deactivate session khi hết hạn hoặc user tắt

### 2.2 Tính Năng Tương Lai (Sprint Sau)

> Chỉ làm khi các tính năng cơ bản đã ổn định và hoàn thiện.

| Tính năng | Mô tả | Độ ưu tiên |
|-----------|-------|------------|
| Social Login | Đăng nhập Google / Apple | Trung bình |
| Premium / Subscription | Lịch sử vị trí 365 ngày, unlimited geofences | Thấp |
| Push Notification (FCM/APNs) | Gửi notification khi app đóng | Cao |
| Playback hành trình | Phát lại hành trình trên bản đồ | Trung bình |
| QR Code invite | Mời thành viên qua QR code | Thấp |
| Driving Report | Báo cáo tốc độ, phanh đột ngột | Thấp |
| Web Dashboard | Quản lý gia đình trên web | Thấp |
| Offline Maps | Bản đồ offline | Thấp |

---

## 3. Kiến Trúc Hệ Thống

### 3.1 Kiến Trúc Tổng Thể

```
┌─────────────────────────────────────────────────────────┐
│                    CLIENT LAYER                         │
│  ┌─────────────────┐       ┌─────────────────────────┐  │
│  │  Flutter App    │       │   Web App (Together     │  │
│  │  (Android/iOS)  │       │   Home - Next.js)       │  │
│  └────────┬────────┘       └────────────┬────────────┘  │
└───────────┼────────────────────────────┼────────────────┘
            │                            │
            ▼                            ▼
┌─────────────────────────────────────────────────────────┐
│                  SUPABASE PLATFORM                      │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Auth        │  │  Realtime    │  │  Storage     │  │
│  │  (JWT)       │  │  (WebSocket) │  │  (chat-      │  │
│  │              │  │              │  │   images)    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │            PostgreSQL Database                   │   │
│  │  profiles | families | family_members |          │   │
│  │  user_locations | latest_locations |             │   │
│  │  geofences | geofence_events | sos_alerts |      │   │
│  │  messages | notifications |                      │   │
│  │  geofence_notification_prefs |                   │   │
│  │  live_location_sessions | users (legacy)         │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │            Edge Functions (Deno)                 │   │
│  │  - check-geofence                                │   │
│  │  - send-sos-notification                         │   │
│  │  - check-inactivity                              │   │
│  │  - send-battery-alert                            │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────┐
│               EXTERNAL SERVICES                         │
│  ┌──────────────────────────┐  ┌─────────────────────┐  │
│  │  OpenStreetMap Tiles     │  │  Nominatim           │  │
│  │  (hoặc Google Maps)      │  │  (Reverse Geocoding) │  │
│  └──────────────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Flutter App Architecture

Sử dụng **Provider pattern** với cấu trúc đơn giản:

```
lib/
├── main.dart                           # Entry point, Supabase init
├── config/
│   └── supabase_config.dart            # Supabase URL & keys
├── models/
│   └── models.dart                     # Data models (FamilyMember, UserLocation, SafeZone, 
│                                       #   AppNotification, ChatMessage, SosAlert)
├── providers/
│   └── app_provider.dart               # ChangeNotifier (state management)
├── screens/
│   ├── login_screen.dart               # Đăng nhập / Đăng ký
│   ├── map_screen.dart                 # Bản đồ chính + SOS + notification badge
│   ├── location_history_screen.dart    # Lịch sử vị trí + Map playback
│   ├── notifications_screen.dart       # Thông báo (geofence/SOS/battery/inactivity)
│   └── chat_screen.dart                # Chat gia đình (text + location sharing)
├── services/
│   ├── supabase_service.dart           # Supabase API wrapper
│   └── location_service.dart           # GPS & background tracking
└── widgets/
    └── map_adapter/
        ├── map_adapter.dart            # Abstract map adapter
        ├── leaflet_adapter.dart        # Leaflet (OpenStreetMap)
        └── google_map_adapter.dart     # Google Maps
```

### 3.3 Data Flow — Location Update

```
User di chuyển
    │
    ▼
LocationService (GPS)
    │  So sánh với vị trí trước:
    │  - Di chuyển > 50m? → Gửi
    │  - Hết 60s max interval? → Gửi
    │  - Đứng yên? → Không gửi
    │
    ▼
Supabase: UPSERT latest_locations
Supabase: INSERT user_locations (history)
    │
    ├──→ Realtime broadcast → Other family members' map updates
    │
    └──→ Edge Function: check-geofence
              │
              └──→ Geofence enter/exit? → INSERT notifications
```

---

## 4. Thiết Kế Database

> **Supabase project:** `mftfgumaftkhjwlavpxh`
> **Migrations path:** `/together-home/supabase/migrations/`

### 4.1 Entity Relationship Diagram

```
auth.users (Supabase Auth)
    │
    ├──→ profiles (1:1, auto-created on signup)
    │
    ├──→ users (1:1, legacy — Flutter compatibility)
    │
    ├──→ family_members ←──→ families
    │         │
    │         └──→ geofences
    │         └──→ messages
    │         └──→ live_location_sessions
    │
    ├──→ user_locations (history, N per user)
    │
    ├──→ latest_locations (1 per user, upsert)
    │
    ├──→ sos_alerts
    │
    ├──→ geofence_events
    │
    ├──→ geofence_notification_prefs
    │
    └──→ notifications
```

### 4.2 Schema Chi Tiết

#### Table: `profiles`

Hồ sơ người dùng — tự động tạo khi đăng ký qua trigger.

```sql
CREATE TABLE public.profiles (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL DEFAULT '',
  avatar_url   TEXT,
  push_token   TEXT,                  -- FCM/APNs token (future)
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### Table: `users` (Legacy — Flutter Compatibility)

> Bảng này tồn tại để tương thích với Flutter app. Dữ liệu được đồng bộ từ `profiles` qua trigger `handle_new_user()`.

```sql
CREATE TABLE public.users (
  id                    UUID PRIMARY KEY,
  name                  TEXT,
  email                 TEXT,
  family_id             TEXT DEFAULT '',
  is_location_sharing   BOOLEAN DEFAULT TRUE,
  created_at            TIMESTAMPTZ DEFAULT now()
);
```

#### Table: `families`

Nhóm gia đình — mỗi family có một `invite_code` unique.

```sql
CREATE TABLE public.families (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE DEFAULT substr(md5(random()::text), 1, 8),
  created_by  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### Table: `family_members`

Quan hệ N:N giữa user và family.

```sql
CREATE TABLE public.family_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role      TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(family_id, user_id)
);
```

#### Table: `user_locations` (Lịch Sử)

Lưu trữ lịch sử vị trí. Auto cleanup sau 30 ngày.

```sql
CREATE TABLE public.user_locations (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  latitude  DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy  DOUBLE PRECISION,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_locations_user_id ON user_locations(user_id);
CREATE INDEX idx_user_locations_timestamp ON user_locations(timestamp DESC);
```

#### Table: `latest_locations` (Vị Trí Mới Nhất)

1 row per user — upsert mỗi khi gửi vị trí mới.

```sql
CREATE TABLE public.latest_locations (
  user_id       UUID PRIMARY KEY,
  latitude      DOUBLE PRECISION NOT NULL,
  longitude     DOUBLE PRECISION NOT NULL,
  accuracy      DOUBLE PRECISION,
  speed         DOUBLE PRECISION,
  heading       DOUBLE PRECISION,
  is_moving     BOOLEAN DEFAULT false,
  battery_level SMALLINT DEFAULT NULL CHECK (battery_level IS NULL OR (battery_level >= 0 AND battery_level <= 100)),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### Table: `geofences` (Vùng An Toàn)

```sql
CREATE TABLE public.geofences (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id     UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  latitude      DOUBLE PRECISION NOT NULL,
  longitude     DOUBLE PRECISION NOT NULL,
  radius_meters DOUBLE PRECISION NOT NULL DEFAULT 500,
  created_by    UUID NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### Table: `geofence_events`

Ghi lại sự kiện enter/exit geofence.

```sql
CREATE TABLE public.geofence_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL,
  geofence_id UUID NOT NULL REFERENCES public.geofences(id) ON DELETE CASCADE,
  event_type  TEXT NOT NULL CHECK (event_type IN ('enter', 'exit')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_geofence_events_user_geofence ON geofence_events(user_id, geofence_id);
```

#### Table: `geofence_notification_prefs`

Tùy chỉnh notification per-user, per-geofence.

```sql
CREATE TABLE public.geofence_notification_prefs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL,
  geofence_id UUID NOT NULL REFERENCES public.geofences(id) ON DELETE CASCADE,
  notify_enter BOOLEAN NOT NULL DEFAULT true,
  notify_exit  BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, geofence_id)
);
```

#### Table: `sos_alerts`

```sql
CREATE TABLE public.sos_alerts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL,
  latitude   DOUBLE PRECISION NOT NULL,
  longitude  DOUBLE PRECISION NOT NULL,
  message    TEXT DEFAULT 'SOS - Cần giúp đỡ!',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

#### Table: `messages` (Chat)

```sql
CREATE TABLE public.messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id    UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  content      TEXT,                        -- text (nullable nếu chỉ gửi ảnh/location)
  image_url    TEXT,                        -- URL ảnh từ Storage
  location_lat DOUBLE PRECISION,            -- chia sẻ vị trí
  location_lng DOUBLE PRECISION,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_family_created ON messages(family_id, created_at DESC);
```

#### Table: `notifications`

```sql
CREATE TABLE public.notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  type       TEXT NOT NULL DEFAULT 'geofence',  -- 'geofence' | 'sos' | 'battery_low' | 'inactivity_alert'
  read       BOOLEAN NOT NULL DEFAULT false,
  metadata   JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user_unread ON notifications(user_id, read) WHERE read = false;
```

#### Table: `live_location_sessions`

```sql
CREATE TABLE public.live_location_sessions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL,
  family_id  UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  is_active  BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 4.3 Database Functions

#### `handle_new_user()` — Auto-Setup Khi Đăng Ký

Trigger chạy sau khi INSERT vào `auth.users`. Thực hiện:

1. Tạo record trong `profiles` (display_name từ metadata hoặc email)
2. Tạo record trong `users` (legacy compatibility)
3. Nếu có `invite_code` trong metadata → tự động join family (case-insensitive lookup)

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    _display_name TEXT;
    _invite_code TEXT;
    _family_id UUID;
BEGIN
    _display_name := COALESCE(
        NEW.raw_user_meta_data->>'display_name',
        NEW.raw_user_meta_data->>'name',
        NEW.email, 'User'
    );
    _invite_code := NEW.raw_user_meta_data->>'invite_code';

    -- 1. Tạo profile
    INSERT INTO public.profiles (user_id, display_name, updated_at)
    VALUES (NEW.id, _display_name, NOW())
    ON CONFLICT (user_id) DO UPDATE SET display_name = EXCLUDED.display_name;

    -- 2. Sync legacy users table
    BEGIN
        INSERT INTO public.users (id, name, email, family_id, is_location_sharing, created_at)
        VALUES (NEW.id, _display_name, NEW.email, '', TRUE, NOW())
        ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, email = EXCLUDED.email;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- 3. Auto-join family nếu có invite_code
    IF _invite_code IS NOT NULL AND _invite_code <> '' THEN
        SELECT id INTO _family_id FROM public.families
        WHERE UPPER(TRIM(invite_code)) = UPPER(TRIM(_invite_code)) LIMIT 1;

        IF _family_id IS NOT NULL THEN
            INSERT INTO public.family_members (family_id, user_id, role)
            VALUES (_family_id, NEW.id, 'member')
            ON CONFLICT (family_id, user_id) DO NOTHING;

            UPDATE public.users SET family_id = _family_id::text WHERE id = NEW.id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
```

#### Helper Functions

```sql
-- Kiểm tra 2 user có cùng family không
CREATE OR REPLACE FUNCTION public.is_family_member(_user_id UUID, _target_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM family_members fm1
    JOIN family_members fm2 ON fm1.family_id = fm2.family_id
    WHERE fm1.user_id = _user_id AND fm2.user_id = _target_user_id
  )
$$;

-- Kiểm tra user có thuộc family không
CREATE OR REPLACE FUNCTION public.is_member_of_family(_user_id UUID, _family_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM family_members WHERE user_id = _user_id AND family_id = _family_id
  )
$$;

-- Cleanup lịch sử > 30 ngày
CREATE OR REPLACE FUNCTION public.cleanup_old_locations()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM user_locations WHERE timestamp < now() - interval '30 days';
END;
$$;
```

### 4.4 Row Level Security (RLS)

Tất cả các bảng đều bật RLS. Nguyên tắc:

- **User chỉ đọc/sửa dữ liệu của mình** (profile, location, notifications)
- **Thành viên cùng family mới xem được dữ liệu nhau** (location, geofence, messages)
- **Admin có quyền quản lý** (xóa thành viên, tạo/xóa geofence)

#### Profiles

| Policy | Action | Rule |
|--------|--------|------|
| View own profile | SELECT | `auth.uid() = user_id` |
| View family member profiles | SELECT | `is_family_member(auth.uid(), user_id)` |
| Update own profile | UPDATE | `auth.uid() = user_id` |
| Insert own profile | INSERT | `auth.uid() = user_id` |

#### Families

| Policy | Action | Rule |
|--------|--------|------|
| Anyone can look up by invite code | SELECT | `true` (authenticated) |
| Create family | INSERT | `auth.uid() = created_by` |
| Admin can update | UPDATE | Admin role check |

#### Family Members

| Policy | Action | Rule |
|--------|--------|------|
| View members | SELECT | `is_member_of_family(auth.uid(), family_id)` |
| Join family | INSERT | `auth.uid() = user_id` |
| Leave family | DELETE | `auth.uid() = user_id` |
| Admin remove members | DELETE | Admin role check |

#### Locations

| Policy | Action | Rule |
|--------|--------|------|
| Insert own location | INSERT | `auth.uid() = user_id` |
| View own / family locations | SELECT | `auth.uid() = user_id` OR `is_family_member()` |
| Upsert latest_locations | ALL | `auth.uid() = user_id` |

#### Messages

| Policy | Action | Rule |
|--------|--------|------|
| View messages | SELECT | `is_member_of_family(auth.uid(), family_id)` |
| Send messages | INSERT | `auth.uid() = user_id AND is_member_of_family()` |

#### Geofences

| Policy | Action | Rule |
|--------|--------|------|
| View geofences | SELECT | `is_member_of_family(auth.uid(), family_id)` |
| Create/Delete | INSERT/DELETE | Admin role check |

#### Notifications

| Policy | Action | Rule |
|--------|--------|------|
| View own | SELECT | `auth.uid() = user_id` |
| Update own (mark read) | UPDATE | `auth.uid() = user_id` |
| Delete own | DELETE | `auth.uid() = user_id` |
| Service can insert | INSERT | `true` (authenticated) |

### 4.5 Realtime Subscriptions

Các bảng có bật Supabase Realtime:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.latest_locations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.live_location_sessions;
```

---

## 5. Edge Functions

> **Path:** `/together-home/supabase/functions/`
> **Runtime:** Deno (Supabase Edge Functions)

### 5.1 `check-geofence`

**Trigger:** Được gọi từ Flutter app mỗi khi gửi vị trí mới.

**Logic:**
1. Lấy family của user qua `family_members`
2. Lấy tất cả `geofences` của family đó
3. Tính khoảng cách (Haversine) từ vị trí user đến mỗi geofence
4. So sánh với `geofence_events` cuối cùng để phát hiện enter/exit
5. Nếu có sự kiện → insert `geofence_events` + insert `notifications` (tôn trọng `geofence_notification_prefs`)

**Config:** `verify_jwt = false`

### 5.2 `send-sos-notification`

**Trigger:** Được gọi khi user bấm SOS.

**Logic:**
1. Xác thực user qua Authorization header
2. Lấy profile + family membership
3. Lấy push tokens của tất cả thành viên family (trừ sender)
4. Log thông báo (push notification qua FCM sẽ implement sau)

**Config:** `verify_jwt = false`

### 5.3 `check-inactivity`

**Trigger:** Scheduled (pg_cron mỗi 15 phút).

**Logic:**
1. Tìm users có `is_moving = false` VÀ `updated_at` > 4h trước
2. Rate-limit: không gửi lại trong 2× threshold
3. Gửi notification cho family members

### 5.4 `send-battery-alert`

**Trigger:** Được gọi từ Flutter app khi battery < 20%.

**Logic:**
1. Xác thực user
2. Gửi notification "Pin thấp" cho tất cả family members

---

## 6. Thiết Kế Flutter App

### 6.1 Dependencies Chính (`pubspec.yaml`)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.5.0

  # Map
  flutter_map: ^7.0.0        # Leaflet wrapper
  latlong2: ^0.9.0
  google_maps_flutter: ...    # Google Maps (optional)

  # Location
  geolocator: ^13.0.0

  # State Management
  provider: ...               # ChangeNotifier pattern

  # Utils
  flutter_dotenv: ...         # Environment variables
```

### 6.2 Location Service — Thuật Toán Gửi Vị Trí Thông Minh

```
┌──────────────────────────────────────┐
│  Lấy vị trí GPS hiện tại            │
└──────────────┬───────────────────────┘
               │
               ▼
┌──────────────────────────────────────┐
│  Khoảng cách so với vị trí trước     │
│  > 50m?                              │
│  ├── CÓ  → Gửi ngay (đang di chuyển)│
│  └── KHÔNG → Kiểm tra thời gian     │
│       > 60s kể từ lần gửi cuối?     │
│       ├── CÓ  → Gửi (keep-alive)    │
│       └── KHÔNG → Bỏ qua            │
└──────────────────────────────────────┘
```

**Mục đích:** Tiết kiệm pin và data. Không gửi liên tục khi đứng yên.

### 6.3 Map Adapter Pattern

Hỗ trợ chuyển đổi giữa Leaflet (miễn phí) và Google Maps:

```dart
abstract class MapAdapter {
  Widget buildMap(/* params */);
}

class LeafletAdapter implements MapAdapter { ... }
class GoogleMapAdapter implements MapAdapter { ... }
```

---

## 7. Supabase Configuration

### 7.1 Project Info

```
Project ID:  mftfgumaftkhjwlavpxh
Region:      (Supabase Cloud)
```

### 7.2 Storage Buckets

| Bucket | Public | Mô tả |
|--------|--------|-------|
| `chat-images` | ✅ | Ảnh trong chat |

### 7.3 Environment Variables

```bash
# .env (Flutter app)
SUPABASE_URL=https://mftfgumaftkhjwlavpxh.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...

# Edge Functions (tự động có từ Supabase)
SUPABASE_URL=...
SUPABASE_SERVICE_ROLE_KEY=...
```

### 7.4 Supabase CLI

```bash
# Deploy migrations
supabase db push

# Deploy Edge Functions
supabase functions deploy check-geofence
supabase functions deploy send-sos-notification
supabase functions deploy check-inactivity
supabase functions deploy send-battery-alert
```

---

## 8. Security & Privacy

### 8.1 Nguyên Tắc

- **Đơn giản nhưng an toàn:** RLS bảo vệ mọi bảng, không cần phức tạp hóa
- **Consent-based:** User phải chủ động join family qua invite code
- **User control:** User có thể tắt location sharing hoặc rời family bất cứ lúc nào
- **Data minimization:** Auto cleanup location history sau 30 ngày
- **Encryption in transit:** HTTPS cho mọi kết nối

### 8.2 Auth Flow Đơn Giản

```
1. User nhập email + password + (optional) invite_code
2. Supabase Auth tạo account
3. Trigger handle_new_user() tự động:
   a. Tạo profiles record
   b. Tạo users record (legacy)
   c. Nếu có invite_code → tự động join family
4. User vào app ngay → thấy bản đồ + thành viên family
```

> **Không cần:** Email verification, phone verification, captcha, approval flow
> **Sẽ thêm sau nếu cần:** Email verification (tùy chọn), Social Login

### 8.3 Data Retention

| Loại dữ liệu | Thời gian lưu |
|---|---|
| Location history | 30 ngày (auto cleanup) |
| Messages | Không giới hạn (hiện tại) |
| Geofence events | Không giới hạn (hiện tại) |
| SOS alerts | Không giới hạn (hiện tại) |
| Notifications | Xóa bởi user |

---

## 9. Lộ Trình Phát Triển

### Sprint 1 ✅ (Hoàn thành): Nền Tảng

- [x] Setup Flutter project + Supabase
- [x] Database schema: profiles, families, family_members, user_locations, latest_locations
- [x] Auth đơn giản (email/password)
- [x] Family management (tạo, join via invite code)
- [x] Real-time location tracking + map display
- [x] Location service với thuật toán thông minh

### Sprint 2 ✅ (Hoàn thành): Tính Năng Cốt Lõi

- [x] Geofencing + Edge Function check-geofence
- [x] SOS alerts + Edge Function send-sos-notification
- [x] In-app messaging (text, image, location sharing)
- [x] Notifications system
- [x] Battery alert + Inactivity alert
- [x] Geofence notification preferences
- [x] Live location sessions

### Sprint 3 🔄 (Hiện tại): Hoàn Thiện & Tối Ưu

- [x] Location history UI (playback hành trình trên bản đồ + timeline slider)
- [x] SOS alerts UI (nút SOS + Edge Function + confirmation dialog)
- [x] Notifications screen (geofence/SOS/battery/inactivity + realtime badge)
- [x] Chat / Messaging screen (text + share location + realtime)
- [x] Admin management UI (xóa thành viên, role badge)
- [x] UI/UX polish (app title, geofence radius input, notification badge)
- [ ] Check-geofence auto-call khi update location
- [ ] Image upload cho chat (Storage bucket `chat-images`)
- [ ] Profile edit screen
- [ ] Performance optimization
- [ ] Bug fixes từ Sprint 1-2

### Sprint 4 (Tương lai): Push & Social

- [ ] FCM Push Notifications (khi app đóng)
- [ ] Social Login (Google / Apple)
- [ ] QR code invite
- [ ] Profile avatar upload

### Sprint 5+ (Tương lai): Nâng Cao

- [ ] Premium subscription (lịch sử 365 ngày, unlimited geofences)
- [ ] Driving Report
- [ ] Web Dashboard (Flutter Web / Next.js)
- [ ] Offline maps
- [ ] Multi-device support

---

## Phụ Lục: Cấu Trúc Thư Mục Supabase

```
together-home/supabase/
├── config.toml
├── migrations/
│   ├── 20250314000001_sprint1_battery_level.sql
│   ├── 20260308153518_..._initial_schema.sql        # profiles, families, family_members, user_locations, RLS
│   ├── 20260308153725_..._family_select_policy.sql   # Open family lookup by invite code
│   ├── 20260308154552_..._family_member_rls_fix.sql  # Security definer function
│   ├── 20260308162949_..._sos_geofences.sql          # sos_alerts, geofences
│   ├── 20260308163813_..._messages.sql               # messages table
│   ├── 20260308164158_..._message_media.sql          # image_url, location sharing in chat
│   ├── 20260308165116_..._latest_locations.sql       # latest_locations + cleanup
│   ├── 20260309021624_..._geofence_events_notifs.sql # geofence_events, notifications
│   ├── 20260309022132_..._geofence_prefs.sql         # geofence_notification_prefs
│   ├── 20260309022620_..._notification_delete.sql    # Delete notification policy
│   ├── 20260309071504_..._live_sessions.sql          # live_location_sessions
│   ├── 20260310074001_..._admin_remove_member.sql    # Admin can remove family members
│   └── 20260318000000_unify_user_profiles.sql        # Unify profiles + users, auto-join family
└── functions/
    ├── check-geofence/index.ts
    ├── send-sos-notification/index.ts
    ├── check-inactivity/index.ts
    └── send-battery-alert/index.ts
```

---

*Tài liệu này được cập nhật lần cuối: 19/03/2026*
*Phản ánh đúng trạng thái hiện tại của database Supabase và Flutter app*
