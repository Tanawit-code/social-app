// ตั้ง/ถอนสิทธิ์แอดมิน (custom claim `admin`) ให้ผู้ใช้ — ใช้ดูหน้า "รายงานทั้งหมด" ในแอป
//
// วิธีใช้ (ต้องมี service account หรือ gcloud auth application-default login):
//   cd tools && npm install
//   GOOGLE_APPLICATION_CREDENTIALS=key.json node set_admin.mjs <uid> [true|false]
//
// หมายเหตุ: ผู้ใช้ต้องล็อกอินใหม่ (หรือรีเฟรช token) เพื่อให้ claim มีผล
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const [uid, flag = 'true'] = process.argv.slice(2);
if (!uid) {
  console.error('usage: node set_admin.mjs <uid> [true|false]');
  process.exit(1);
}

initializeApp({ credential: applicationDefault() });
const user = await getAuth().getUser(uid);
// setCustomUserClaims ทับทั้งก้อน จึงต้องรวมกับ claim เดิม
await getAuth().setCustomUserClaims(uid, {
  ...(user.customClaims ?? {}),
  admin: flag === 'true',
});
console.log(`${uid} admin = ${flag === 'true'}`);
