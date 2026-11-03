# SonTaNa — Social Network App

แอปโซเชียลเน็ตเวิร์กภาษาไทยที่สร้างด้วย **Flutter + Firebase** (Authentication, Cloud Firestore, Cloud Messaging, Cloud Functions)
รองรับ Android, iOS, เว็บ และเดสก์ท็อป (ทดสอบหลักบน Android และ Chrome)

## สารบัญ

- [ฟีเจอร์](#ฟีเจอร์)
- [เทคโนโลยี](#เทคโนโลยี)
- [โครงสร้างโปรเจกต์](#โครงสร้างโปรเจกต์)
- [เริ่มต้นใช้งาน](#เริ่มต้นใช้งาน)
- [การ Deploy](#การ-deploy)
- [การทดสอบ](#การทดสอบ)
- [ระบบดูแลเนื้อหาและแอดมิน](#ระบบดูแลเนื้อหาและแอดมิน)
- [การย้าย region และสำรองข้อมูล Firestore](#การย้าย-region-และสำรองข้อมูล-firestore)
- [แก้ปัญหาที่พบบ่อย](#แก้ปัญหาที่พบบ่อย)
- [ข้อจำกัดที่ทราบ](#ข้อจำกัดที่ทราบ)
- [ข้อควรระวัง](#ข้อควรระวัง)

## ฟีเจอร์

**บัญชีและความสัมพันธ์**
- สมัครสมาชิก / เข้าสู่ระบบ / รีเซ็ตรหัสผ่าน / เปลี่ยนอีเมล / ลบบัญชี
- โปรไฟล์: แก้ชื่อ, bio, รูปโปรไฟล์, รูปปก, บัญชีส่วนตัว (private)
- ติดตาม / เลิกติดตาม, คำขอติดตามบัญชีส่วนตัว, เพื่อน, บล็อก, ปิดการมองเห็นโพสต์ของผู้เขียน (mute), ซ่อนโพสต์
- แนะนำให้ติดตามบนหน้าฟีด

**เนื้อหา**
- โพสต์ข้อความ รูป (สูงสุด 4 รูปต่อโพสต์) และวิดีโอ พร้อมกำหนดผู้ที่เห็น (สาธารณะ / เพื่อน / ส่วนตัว)
- แชร์โพสต์, แท็กผู้ใช้ด้วย `@mention` พร้อมแจ้งเตือน
- รีแอคชัน 8 แบบ (like, dislike, love, care, haha, wow, sad, angry) และความคิดเห็น
- **Story** (หมดอายุใน 24 ชั่วโมง) เลือกสีพื้นหลัง รูป และผู้ที่เห็นได้
- **Reels** (วิดีโอสั้น)
- **ชุมชน (Communities)** พร้อมบทบาท owner / moderator / member, คำขอเข้าร่วม, แบน, ปักหมุดโพสต์
- **เพจ (Pages)** พร้อมผู้ดูแล, คำขอเป็นสมาชิก, แบน
- **อีเวนต์ (Events)** ตอบรับ going / interested และยกเลิกอีเวนต์
- เจ้าของชุมชน/เพจตกแต่งรูปปกและสีธีมได้

**แชท**
- แชท 1:1 และแชทกลุ่ม ส่งข้อความ รูป วิดีโอ และ 👍
- ลบข้อความ (แสดงเป็น "ข้อความถูกลบ" ทั้งสองฝั่ง)
- **ลบประวัติแชท** และ **ลบแชท** แยกกัน (มีผลเฉพาะฝั่งตัวเอง)
- กลุ่ม: เจ้าของเพิ่มสมาชิกจากคนที่ตัวเองติดตาม (สูงสุด 50 คน), เตะสมาชิก, สมาชิกออกเอง, เจ้าของออกแล้วโอนกลุ่มให้คนถัดไป
- ตัวเลขข้อความที่ยังไม่อ่าน

**ค้นหาและแจ้งเตือน**
- ค้นหา 5 หมวด: ผู้ใช้ / โพสต์ / ชุมชน / เพจ / อีเวนต์ พร้อมตัวกรองและปุ่มโหลดเพิ่ม
- แจ้งเตือนในแอป และ push notification (FCM) ที่กดแล้วเข้าห้องแชทตรงๆ

**ความปลอดภัยและการดูแลเนื้อหา**
- รายงานโพสต์ / โปรไฟล์ / ความคิดเห็น / ข้อความแชท / เพจ / ชุมชน / อีเวนต์
- ระบบซ่อนโพสต์อัตโนมัติเมื่อมีผู้รายงานครบเกณฑ์ (ดู [ระบบดูแลเนื้อหาและแอดมิน](#ระบบดูแลเนื้อหาและแอดมิน))
- หน้ารายงานทั้งหมดสำหรับแอดมิน

## เทคโนโลยี

| ส่วน | ใช้อะไร |
|---|---|
| แอป | Flutter (Dart ^3.12), Material 3 |
| ฐานข้อมูล / Auth | Cloud Firestore, Firebase Authentication |
| Push | Firebase Cloud Messaging + Cloud Functions (`functions/`, Node.js 22) |
| รูปภาพ | ย่อขนาดแล้วเก็บเป็น data URL (base64) ในเอกสาร Firestore ไม่ใช้ Firebase Storage |
| วิดีโอ | Cloudinary เก็บเฉพาะ URL ใน Firestore |
| โปรเจกต์ Firebase | `social-app-3569a` (ตั้งใน `.firebaserc`) |
| Firestore location | `asia-southeast1` (สิงคโปร์) |

> **เรื่องขนาดรูป:** เอกสาร Firestore ใหญ่ได้ไม่เกิน 1 MiB จึงจำกัดขนาดรูปในโค้ดและใน rules
> (รูปโพสต์ ~250 KB ต่อรูป และรวมต่อโพสต์ ~640 KB, รูป Story ไม่เกิน 350,000 ตัวอักษรของ base64)

## โครงสร้างโปรเจกต์

```
lib/
  main.dart
  firebase_options.dart        # สร้างด้วย flutterfire configure
  models/                      # โมเดลข้อมูล (post, story, community, event)
  services/                    # ตัวคุยกับ Firebase (auth, chat, follow, post, story, push ...)
  screens/                     # หน้าจอทั้งหมด
  widgets/                     # วิดเจ็ตที่ใช้ร่วมกัน (story_strip, reactions, post_media ...)
  theme/                       # ธีมแอป
  utils/                       # validators, image_data, mention, time_ago
functions/                     # Cloud Functions (push, moderation, ลบบัญชี, รีเซ็ตรหัสผ่าน)
rules-tests/                   # เทสต์ของ Firestore Security Rules (ใช้ Emulator)
test/                          # Flutter unit/widget tests
tools/                         # สคริปต์ผู้ดูแล (set_admin, migrate_legacy_post_audience)
firestore.rules                # Security Rules
firestore.indexes.json         # Composite indexes
storage.rules                  # ปิดทั้งหมด (แอปไม่ใช้ Firebase Storage)
firebase.json / .firebaserc    # ตั้งค่า Firebase CLI
```

## เริ่มต้นใช้งาน

### สิ่งที่ต้องมี
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.12)
- [Node.js](https://nodejs.org) 22 (ตรงกับ `functions/package.json`) และ Firebase CLI: `npm install -g firebase-tools`
- JDK 21 ขึ้นไป (เฉพาะตอนรันเทสต์ rules ด้วย Firestore Emulator)

### ตั้งค่า
```bash
flutter pub get
firebase login
```
ค่าเชื่อมต่อแอปอยู่ใน `lib/firebase_options.dart` และ `android/app/google-services.json`
ถ้าจะใช้โปรเจกต์ Firebase ของตัวเอง ให้รัน `flutterfire configure` แล้วแก้ `.firebaserc` ให้ตรงกัน

### ตั้งค่า Cloudinary (อัปโหลดวิดีโอ)
แก้ `cloudName` และ `uploadPreset` ใน `lib/services/video_upload_service.dart` ให้เป็นของบัญชี Cloudinary ของคุณ
(upload preset ต้องเป็นแบบ unsigned; วิดีโอไม่เกิน 30 MB / 60 วินาที)

### รันแอป
```bash
flutter run                              # อุปกรณ์/อีมูเลเตอร์ที่เชื่อมอยู่
flutter run -d chrome --web-port 5000    # เว็บ
```
- ทดสอบ 2 บัญชีพร้อมกันบนเว็บ: เปิด `http://localhost:5000` ใน Chrome ปกติ และอีกบัญชีใน **หน้าต่างไม่ระบุตัวตน (Incognito)**
- พอร์ตคงที่ (`--web-port`) ช่วยไม่ให้ต้องล็อกอินใหม่ทุกครั้งที่รัน

## การ Deploy

| สิ่งที่แก้ | คำสั่ง |
|---|---|
| `firestore.rules` | `firebase deploy --only firestore:rules` |
| `firestore.indexes.json` | `firebase deploy --only firestore:indexes` |
| rules + indexes พร้อมกัน | `firebase deploy --only firestore` |
| `functions/` | `cd functions && npm install && cd .. && firebase deploy --only functions` |

> **สำคัญ:** แก้ `firestore.rules` หรือแก้โค้ดแอปที่เขียนฟิลด์ใหม่ลง Firestore แล้วลืม deploy rules
> จะเจอ `permission-denied` ในแอป เพราะ rules ตรวจฟิลด์แบบ `hasOnly([...])` ฟิลด์ที่ไม่อยู่ในรายการจะถูกปฏิเสธ
> (เช่น ถ้าเพิ่มฟิลด์ใหม่ใน `StoryService.create()` ต้องเพิ่มชื่อฟิลด์นั้นใน rules ของ `stories` ด้วย)

### Cloud Functions

Cloud Functions ต้องใช้แผน **Blaze** ฟังก์ชันที่มี:

| ฟังก์ชัน | หน้าที่ |
|---|---|
| `sendUserPush` | ส่ง push notification เมื่อมีเอกสารแจ้งเตือนใหม่ |
| `checkEmailForReset` | ตรวจอีเมลก่อนรีเซ็ตรหัสผ่าน |
| `deleteMyAccount` | ลบบัญชีพร้อมข้อมูลที่เกี่ยวข้อง (รวมวิดีโอบน Cloudinary) |
| `onReportCreated`, `mirrorCommunityReport` | รับรายงานและนับจำนวนผู้รายงาน |
| `onPostEdited`, `onCommunityPostEdited` | ตรวจการแก้ไขโพสต์ที่ถูกซ่อน |
| `moderatePost` | ให้แอดมิน/ผู้ดูแลจัดการโพสต์ที่ถูกรายงาน |

ฟังก์ชันลบบัญชีใช้ secret สำหรับ Cloudinary:
```bash
firebase functions:secrets:set CLOUDINARY_API_KEY
firebase functions:secrets:set CLOUDINARY_API_SECRET
```

> ฟังก์ชันไม่ได้ตั้ง region ไว้ จึงอยู่ที่ค่าเริ่มต้น (`us-central1`) ส่วน Firestore อยู่ `asia-southeast1`
> การ deploy จะมี warning เรื่อง cross-region ซึ่งใช้งานได้ปกติ แต่มี latency เพิ่มเล็กน้อย
> ถ้าต้องการให้อยู่ region เดียวกัน ให้ตั้ง `setGlobalOptions({ region: 'asia-southeast1' })` ใน `functions/index.js`

## การทดสอบ

```bash
flutter analyze          # วิเคราะห์โค้ด
flutter test             # unit / widget tests (test/)
```

### ทดสอบ Firestore Security Rules
ใช้ Firestore Emulator และ Node test runner (ไม่แตะข้อมูลจริง)
```bash
cd rules-tests
npm install
npm test
```
ครั้งแรก Firebase CLI จะดาวน์โหลด emulator ให้อัตโนมัติ เทสต์ปัจจุบันครอบคลุม users, posts/comments,
แชท 1:1, ข้อความ, chatStates และกลุ่มแชท

> ยังไม่มีเทสต์ของ `stories`, `communities`, `pages`, `events` และ `reports` ควรเพิ่มเมื่อแก้ rules ในส่วนนั้น

### ทดสอบ Cloud Functions (ตรรกะซ่อนโพสต์)
```bash
cd functions
node --test
```

## ระบบดูแลเนื้อหาและแอดมิน

- ผู้ใช้รายงานได้ที่โพสต์ โปรไฟล์ ความคิดเห็น ข้อความแชท เพจ ชุมชน และอีเวนต์
  (เอกสารรายงานมี id รูปแบบ `{reporter}_{targetType}_{targetId}` เพื่อกันรายงานซ้ำ)
- โพสต์ที่มีผู้รายงานที่ยัง active (`open` / `reviewing`) ครบ **3 คน** จะถูกซ่อนโดยระบบ
  เจ้าของโพสต์และแอดมินยังเห็นโพสต์นั้นเสมอ
- เจ้าของโพสต์แก้ไขเนื้อหาแล้วระบบจะตรวจว่าเปลี่ยนจริง (อย่างน้อย ~10% และ 3 ตัวอักษร) ก่อนพิจารณาเลิกซ่อน
- ฟิลด์ `hidden*` เขียนได้เฉพาะฝั่งเซิร์ฟเวอร์ (Cloud Functions)

### ตั้งสิทธิ์แอดมิน
แอดมินคือผู้ใช้ที่มี custom claim `admin: true` ใช้ดูหน้า "รายงานทั้งหมด" ในแอป
```bash
cd tools
npm install
# ต้องมี service account หรือรัน gcloud auth application-default login
GOOGLE_APPLICATION_CREDENTIALS=key.json node set_admin.mjs <uid> true    # ถอนสิทธิ์: false
```
ผู้ใช้ต้องล็อกอินใหม่เพื่อให้ claim มีผล

## การย้าย region และสำรองข้อมูล Firestore

Location ของ database เปลี่ยนไม่ได้ ถ้าจะย้ายต้อง **export → ลบ → สร้างใหม่ → import** (ข้อมูลหายถ้าไม่ได้สำรอง)

```bash
# 1) สำรอง (bucket ต้องอยู่ region เดียวกับ database ปัจจุบัน)
gcloud storage buckets create gs://<PROJECT_ID>-firestore-backup --location=<REGION_เดิม>
gcloud firestore export gs://<PROJECT_ID>-firestore-backup/backup-YYYY-MM-DD
gcloud firestore operations list        # รอจน operationState: SUCCESSFUL
gcloud storage ls -r gs://<PROJECT_ID>-firestore-backup/backup-YYYY-MM-DD

# 2) ลบและสร้างใหม่ (หลังลบต้องรอราว 5 นาทีก่อนสร้างชื่อ (default) ซ้ำได้)
firebase firestore:databases:delete "(default)"
firebase firestore:databases:create "(default)" --location <REGION_ใหม่>

# 3) import (bucket ต้องอยู่ region เดียวกับ database ใหม่ หรือ multi-region ที่ครอบคลุม)
gcloud storage buckets create gs://<PROJECT_ID>-firestore-new --location=<REGION_ใหม่>
gcloud storage cp -r gs://<PROJECT_ID>-firestore-backup/backup-YYYY-MM-DD gs://<PROJECT_ID>-firestore-new/
gcloud firestore import gs://<PROJECT_ID>-firestore-new/backup-YYYY-MM-DD

# 4) ใส่ rules และ indexes กลับ (export ไม่เก็บสองอย่างนี้)
firebase deploy --only firestore
```

ข้อควรรู้: เปิด Point-in-Time Recovery และ Delete Protection ไว้จะช่วยป้องกันการลบพลาดและกู้ข้อมูลย้อนหลังได้

## แก้ปัญหาที่พบบ่อย

| อาการ | สาเหตุที่พบบ่อย | วิธีแก้ |
|---|---|---|
| `permission-denied` ตอนสร้าง/แก้เอกสาร | แอปส่งฟิลด์ที่ไม่อยู่ใน `hasOnly([...])` ของ rules หรือยังไม่ได้ deploy rules | เทียบฟิลด์ที่แอปเขียนกับ rules แล้ว `firebase deploy --only firestore:rules` |
| ฟีดโหลดไม่ขึ้นพร้อมข้อความเรื่อง index | composite index ยังไม่ถูกสร้าง | `firebase deploy --only firestore:indexes` แล้วรอสถานะ Enabled ใน Console |
| ทุก query ถูกปฏิเสธหลังสร้าง database ใหม่ | database ใหม่ใช้ rules แบบปิดทั้งหมด | `firebase deploy --only firestore` |
| `gcloud firestore import` ฟ้องเรื่อง location ของ bucket | bucket อยู่คนละ region กับ database | คัดลอก backup ไป bucket ที่อยู่ region เดียวกับ database ใหม่ |
| ไม่ได้รับ push ตอนปิดแอป | ยังไม่ได้ deploy functions หรือไม่ได้อยู่บนแผน Blaze | `firebase deploy --only functions` |

## ข้อจำกัดที่ทราบ

- ยังไม่รองรับ web push (ยังไม่มี `firebase-messaging-sw.js`)
- ส่งไฟล์ในแชทได้เฉพาะรูปภาพและวิดีโอ (ไม่มีเอกสารอื่น)
- ไม่มีข้อความแจ้งในกลุ่มว่าใครถูกเพิ่ม / ออก / ถูกเตะ
- การค้นหากรองฝั่งแอปจากข้อมูลล่าสุดที่โหลดมา (ใช้ปุ่ม "โหลดเพิ่ม" เพื่อขยายช่วงค้นหา)
- ไม่มี seen receipt / typing indicator / ตอบกลับข้อความ
- เก็บรูปเป็น base64 ใน Firestore จึงมีเพดานขนาดรูปต่ำ และเปลืองโควตาอ่าน/เขียนมากกว่าการใช้ Storage
- `list` ของโพสต์กรองโพสต์ที่ถูกซ่อนใน rules ไม่ได้ จึงกรองฝั่งแอป (`Post.isHiddenFor`)

## ข้อควรระวัง

- อย่าคอมมิตไฟล์ลับ (`.env`, service account `key.json`, คีย์ API ส่วนตัว) เข้า Git
- โฟลเดอร์สำรองข้อมูล (`local-backup/`), `firestore.indexes.backup.json` และ `log.txt` ไม่ควรเข้า Git
  (ข้อมูลผู้ใช้จริงอยู่ใน backup) เพิ่มใน `.gitignore`:
  ```
  /local-backup/
  /firestore.indexes.backup.json
  /log.txt
  ```
- แก้ `firestore.rules` แล้วต้องรันเทสต์ใน `rules-tests/` และ deploy ก่อนทุกครั้ง