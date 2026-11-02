# Social Network App

แอปโซเชียลเน็ตเวิร์กที่สร้างด้วย **Flutter + Firebase** (Authentication, Cloud Firestore, Cloud Messaging, Cloud Functions)
รองรับทั้งเว็บและมือถือ ออกแบบให้ใช้ได้บนแผน **Firebase ฟรี (Spark)** เป็นหลัก

## ฟีเจอร์

**บัญชีและความสัมพันธ์**
- สมัครสมาชิก / เข้าสู่ระบบ / รีเซ็ตรหัสผ่าน / เปลี่ยนอีเมล / ลบบัญชี
- โปรไฟล์: แก้ชื่อ, bio, รูปโปรไฟล์, รูปปก, บัญชีส่วนตัว (private)
- ติดตาม / เลิกติดตาม, คำขอติดตามบัญชีส่วนตัว, เพื่อน, บล็อก, รายงาน

**เนื้อหา**
- โพสต์ข้อความ รูป (หลายรูปในโพสต์เดียว สูงสุด 4 รูป) วิดีโอ พร้อมกำหนดผู้ที่เห็น (สาธารณะ / เพื่อน / ส่วนตัว) และแชร์โพสต์
- รีแอคชัน 8 แบบ (like, dislike, love, care, haha, wow, sad, angry), ความคิดเห็น, Story, Reels
- หน้าโปรไฟล์แสดงโพสต์จากฟีดส่วนตัว เพจ และชุมชน
- ชุมชน (Communities), เพจ (Pages), อีเวนต์ (Events)

**แชท**
- แชท 1:1 และแชทกลุ่ม ส่งข้อความ รูป และ 👍
- ลบข้อความ (แสดงเป็น "ข้อความถูกลบ" ทั้งสองฝั่ง)
- **ลบประวัติแชท** และ **ลบแชท** แยกกัน (มีผลเฉพาะฝั่งตัวเอง)
- กลุ่ม: เจ้าของเพิ่มเพื่อน (ต้องติดตามกันทั้งสองฝ่าย, สูงสุด 50 คน), เตะสมาชิก, สมาชิกออกจากกลุ่มเอง, เจ้าของออกแล้วโอนกลุ่มให้คนถัดไป
- ตัวเลขข้อความที่ยังไม่อ่าน

**ค้นหาและแจ้งเตือน**
- ค้นหา 5 หมวด: ผู้ใช้ / โพสต์ / ชุมชน / เพจ / อีเวนต์ พร้อมตัวกรอง (ประเภทสื่อ, ช่วงเวลา, ความเป็นส่วนตัว, อีเวนต์ที่ผ่านแล้ว/ยกเลิก) และปุ่มโหลดเพิ่ม
- การแจ้งเตือนในแอป และ push notification (FCM) ที่กดแล้วเข้าห้องแชทตรงๆ

## เทคโนโลยี

| ส่วน | ใช้อะไร |
|---|---|
| แอป | Flutter (Dart ^3.12), Material 3 |
| ฐานข้อมูล / Auth | Cloud Firestore, Firebase Authentication |
| Push | Firebase Cloud Messaging + Cloud Functions (`functions/`) |
| วิดีโอ | Cloudinary (แพ็กเกจฟรี) เก็บเฉพาะ URL ใน Firestore |
| รูปภาพ | ย่อขนาดแล้วเก็บในเอกสาร Firestore (ไม่ใช้ Firebase Storage เพื่อให้ใช้แผนฟรีได้) |

## โครงสร้างโปรเจกต์

```
lib/
  main.dart
  firebase_options.dart        # สร้างด้วย flutterfire configure
  models/                      # โมเดลข้อมูล (post, story, community, event)
  services/                    # ตัวคุยกับ Firebase (auth, chat, follow, post, push ...)
  screens/                     # หน้าจอทั้งหมด
  widgets/                     # วิดเจ็ตที่ใช้ร่วมกัน (avatar, chat_actions, post_media ...)
  utils/                       # validators, image_data
functions/                     # Cloud Functions (push, ลบบัญชี)  *ต้องใช้แผน Blaze
rules-tests/                   # เทสต์ของ Firestore Security Rules
test/                          # Flutter unit/widget tests
firestore.rules                # Security Rules
firestore.indexes.json
storage.rules
tools/                         # สคริปต์ย้ายข้อมูล (migrate_legacy_post_audience.mjs)
```

## เริ่มต้นใช้งาน

### สิ่งที่ต้องมี
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.12)
- [Node.js](https://nodejs.org) 20 ขึ้นไป และ Firebase CLI: `npm install -g firebase-tools`
- JDK 21 ขึ้นไป (เฉพาะตอนรันเทสต์ rules ด้วย Firestore Emulator — firebase-tools รุ่นปัจจุบันไม่รองรับ Java ต่ำกว่า 21)

### ตั้งค่า
```bash
flutter pub get
firebase login
```
โปรเจกต์ Firebase ที่ผูกไว้อยู่ใน `.firebaserc` และค่าเชื่อมต่อแอปอยู่ใน `lib/firebase_options.dart`
ถ้าจะใช้โปรเจกต์ Firebase ของตัวเอง ให้รัน `flutterfire configure` แล้วแก้ `.firebaserc` ให้ตรงกัน

### Deploy Firestore Rules (ทำทุกครั้งที่แก้ `firestore.rules`)
```bash
firebase deploy --only firestore:rules
```
> ถ้าลืม deploy จะเจอ error `permission-denied` ในแอป เพราะกฎบนเซิร์ฟเวอร์ยังเป็นชุดเก่า

### รันแอป
```bash
flutter run -d chrome --web-port 5000
```
- ทดสอบ 2 บัญชีพร้อมกัน: เปิด `http://localhost:5000` ใน Chrome ปกติ และอีกบัญชีใน **หน้าต่างไม่ระบุตัวตน (Incognito)**
- พอร์ตคงที่ (`--web-port`) ช่วยไม่ให้ต้องล็อกอินใหม่ทุกครั้งที่รัน

## การทดสอบ

```bash
flutter analyze          # วิเคราะห์โค้ด
flutter test             # unit / widget tests (test/)
```

### ทดสอบ Firestore Security Rules
ใช้ Firestore Emulator และ Node test runner (ไม่แตะข้อมูลจริงบน Firebase)
```bash
cd rules-tests
npm install
npm test
```
ครั้งแรก Firebase CLI จะดาวน์โหลด emulator ให้อัตโนมัติ เทสต์ครอบคลุม:

| หมวด | ตัวอย่างที่ตรวจ |
|---|---|
| users | อ่านโปรไฟล์ต้องล็อกอิน, แก้โปรไฟล์คนอื่นไม่ได้, สร้างโปรไฟล์ด้วยฟิลด์แปลกปลอมไม่ได้ |
| posts / comments | ปลอม `authorId` ไม่ได้, ยอดไลก์เริ่มต้นต้องเป็น 0, โพสต์หลายรูปไม่เกิน 3 รูปเพิ่ม, การมองเห็น (สาธารณะ/เพื่อน/ส่วนตัว/บล็อก), แก้/ลบได้เฉพาะเจ้าของ |
| chats 1:1 | เปิดห้องที่ยังไม่เคยสร้างต้องไม่ถูกปฏิเสธ (บั๊กเดิม), คนนอกอ่านไม่ได้, ห้องกับคนที่บล็อกกันสร้างไม่ได้ |
| messages | ปลอม `senderId` ไม่ได้, ต้องใช้เวลาเซิร์ฟเวอร์, ข้อความว่างไม่ได้, ลบข้อความได้เฉพาะแบบ soft-delete |
| chatStates | ลบแชท/ลบประวัติเขียนได้เฉพาะของตัวเอง |
| กลุ่มแชท | สร้างกลุ่มกับคนที่ติดตามเท่านั้น, ออกเอง, เตะ, โอนเจ้าของ, เพิ่มสมาชิก (สูงสุด 50), สมาชิกทั่วไปทำแทนเจ้าของไม่ได้ |

## Cloud Functions และข้อจำกัดของแผนฟรี

Cloud Functions ใน `functions/` ต้องใช้แผน **Blaze (pay-as-you-go)** จึงจะ deploy ได้
ถ้ายังไม่อัปเกรด ส่วนที่ไม่ทำงานคือ:
- **push notification ตอนปิดแอป** (`sendUserPush`) — แอปยังแสดงแจ้งเตือนในแอปได้ตามปกติ
- **ลบบัญชีแบบลบข้อมูลครบ** (`functions/account_deletion.js`)

เมื่ออัปเกรดแล้ว:
```bash
cd functions && npm install && cd ..
firebase deploy --only functions
```
ฟังก์ชันลบบัญชีใช้ secret `CLOUDINARY_API_KEY` และ `CLOUDINARY_API_SECRET`
(ตั้งด้วย `firebase functions:secrets:set CLOUDINARY_API_KEY`)

### ตั้งค่า Cloudinary (อัปโหลดวิดีโอ)
แก้ `cloudName` และ `uploadPreset` ใน `lib/services/video_upload_service.dart` ให้เป็นของบัญชี Cloudinary ของคุณ
(วิดีโอไม่เกิน 30 MB / 60 วินาที)

## ข้อจำกัดที่ทราบ
- ยังไม่รองรับ web push (ยังไม่มี `firebase-messaging-sw.js`)
- ส่งไฟล์ในแชทได้เฉพาะรูปภาพ (ไม่มีวิดีโอ/เอกสาร)
- ข้อความแจ้งในกลุ่มว่าใครถูกเพิ่ม / ออก / ถูกเตะ ยังไม่มี
- การค้นหากรองฝั่งแอปจากข้อมูลล่าสุดที่โหลดมา (ใช้ปุ่ม "โหลดเพิ่ม" เพื่อขยายช่วงค้นหา)
- ไม่มี seen receipt / typing indicator / ตอบกลับข้อความ

## ข้อควรระวัง
- อย่าคอมมิตไฟล์ลับ (`.env`, service account, คีย์ API ส่วนตัว) เข้า Git
- แก้ `firestore.rules` แล้วต้อง deploy และรันเทสต์ใน `rules-tests/` ก่อนทุกครั้ง