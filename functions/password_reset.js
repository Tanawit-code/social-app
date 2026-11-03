const crypto = require('node:crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { Timestamp, getFirestore } = require('firebase-admin/firestore');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

if (getApps().length === 0) initializeApp();
const db = getFirestore();

const EMAIL_REGEX = /^[\w.+-]+@[\w-]+\.[\w.-]+$/;
const WINDOW_MS = 15 * 60 * 1000;
const MAX_PER_IP = 20; // ต่อ 15 นาที
const MAX_PER_EMAIL = 5; // ต่อ 15 นาที

function hash(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

// นับจำนวนครั้งในช่วงเวลา (fixed window) คืน true ถ้าเกินลิมิต
// เอกสารใน rateLimits ไม่มี rule ให้ client อ่าน/เขียน (default deny) — ใช้ได้เฉพาะ Admin SDK
// แนะนำให้ตั้ง TTL policy ที่ฟิลด์ expireAt ใน Firestore เพื่อลบเอกสารเก่าอัตโนมัติ
async function isRateLimited(key, max) {
  const ref = db.collection('rateLimits').doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    let { count = 0, windowStart = now } = snap.data() || {};
    if (now - windowStart > WINDOW_MS) {
      count = 0;
      windowStart = now;
    }
    count += 1;
    tx.set(ref, {
      count,
      windowStart,
      expireAt: Timestamp.fromMillis(windowStart + WINDOW_MS),
    });
    return count > max;
  });
}

/**
 * ตรวจก่อนส่งลิงก์รีเซ็ตรหัสผ่านว่าอีเมลนี้มีบัญชีอยู่จริงหรือไม่
 * ใช้ Admin SDK จึงไม่ถูกกระทบจาก "Email Enumeration Protection" ของ Firebase Auth
 * (ถ้าเปิดไว้ sendPasswordResetEmail ฝั่ง client จะตอบสำเร็จเสมอแม้ไม่มีอีเมลนี้)
 */
exports.checkEmailForReset = onCall(async (request) => {
  const email = String(request.data?.email ?? '').trim().toLowerCase();
  if (!EMAIL_REGEX.test(email) || email.length > 254) {
    throw new HttpsError('invalid-argument', 'รูปแบบอีเมลไม่ถูกต้อง');
  }

  const ip = request.rawRequest?.ip || 'unknown';
  const [ipLimited, emailLimited] = await Promise.all([
    isRateLimited(`pwreset_ip_${hash(ip)}`, MAX_PER_IP),
    isRateLimited(`pwreset_email_${hash(email)}`, MAX_PER_EMAIL),
  ]);
  if (ipLimited || emailLimited) {
    throw new HttpsError(
      'resource-exhausted',
      'ขอลิงก์บ่อยเกินไป กรุณารอ 15 นาทีแล้วลองใหม่',
    );
  }

  try {
    const user = await getAuth().getUserByEmail(email);
    if (user.disabled) {
      throw new HttpsError('failed-precondition', 'บัญชีนี้ถูกระงับการใช้งาน');
    }
    return { exists: true };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (error.code === 'auth/user-not-found') {
      throw new HttpsError('not-found', 'ไม่พบอีเมลนี้ในระบบ กรุณาตรวจสอบอีเมลหรือสมัครสมาชิกก่อน');
    }
    console.error('checkEmailForReset failed', error);
    throw new HttpsError('internal', 'ตรวจสอบอีเมลไม่สำเร็จ กรุณาลองใหม่');
  }
});
