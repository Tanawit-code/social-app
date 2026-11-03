// ตรรกะล้วน (ไม่ผูกกับ Firebase) ของระบบซ่อนโพสต์ — แยกไว้เพื่อให้ทดสอบด้วย `node --test` ได้

/** จำนวนผู้รายงานขั้นต่ำที่ทำให้ระบบซ่อนโพสต์อัตโนมัติ ("มากกว่า 2 คน" = 3 คนขึ้นไป) */
const REPORT_HIDE_THRESHOLD = 3;

/** สถานะรายงานที่ยังนับรวมในการซ่อน (รายงานที่ปิด/ยกเลิกแล้วไม่นับ) */
const ACTIVE_REPORT_STATUSES = ['open', 'reviewing'];

/** การแก้ไขต้องเปลี่ยนเนื้อหาอย่างน้อยกี่ % ถึงนับว่า "แก้ไขจริง" */
const MIN_CHANGE_RATIO = 0.1;
/** ...และต้องเปลี่ยนอย่างน้อยกี่ตัวอักษร (กันแก้แค่ 1-2 ตัวเพื่อหลบ) */
const MIN_CHANGED_CHARS = 3;
/** ข้อความยาวกว่านี้ใช้วิธีเทียบ 3-gram แทน Levenshtein (กันช้า) */
const LEVENSHTEIN_MAX_LEN = 1500;

/** ทำข้อความให้เทียบกันได้: ตัวพิมพ์เล็ก, ตัดช่องว่าง/เครื่องหมาย/zero-width */
function normalizeText(input) {
  return String(input ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[​-‍﻿]/g, '')
    .replace(/[^\p{L}\p{N}\p{M}]+/gu, '');
}

function levenshtein(a, b) {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  const x = Array.from(a);
  const y = Array.from(b);
  let prev = Array.from({ length: y.length + 1 }, (_, i) => i);
  for (let i = 1; i <= x.length; i++) {
    const cur = [i];
    for (let j = 1; j <= y.length; j++) {
      cur[j] = Math.min(
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + (x[i - 1] === y[j - 1] ? 0 : 1),
      );
    }
    prev = cur;
  }
  return prev[y.length];
}

function trigrams(s) {
  const chars = Array.from(s);
  const set = new Set();
  for (let i = 0; i + 3 <= chars.length; i++) set.add(chars.slice(i, i + 3).join(''));
  return set;
}

/**
 * ตรวจว่าการแก้ไขหลังโพสต์ถูกซ่อนเป็นการแก้ไขจริงหรือไม่
 * @param {string} original เนื้อหาตอนถูกซ่อน
 * @param {string} edited เนื้อหาหลังแก้
 * @param {{hasMedia?: boolean}} opts hasMedia = โพสต์มีรูป/วิดีโอ (ลบข้อความทิ้งทั้งหมดได้)
 * @returns {{ok: boolean, reason: string, ratio: number}}
 */
function evaluateEdit(original, edited, opts = {}) {
  const a = normalizeText(original);
  const b = normalizeText(edited);
  if (a === b) {
    return { ok: false, ratio: 0, reason: 'เนื้อหาไม่ได้เปลี่ยนแปลง (แก้เฉพาะช่องว่างหรือเครื่องหมาย)' };
  }
  if (!b) {
    return opts.hasMedia
      ? { ok: true, ratio: 1, reason: 'ลบข้อความที่ถูกรายงานออกแล้ว' }
      : { ok: false, ratio: 1, reason: 'โพสต์ว่างเปล่า กรุณาแก้ไขเนื้อหาให้เหมาะสมแทนการลบข้อความทั้งหมด' };
  }
  const longest = Math.max(Array.from(a).length, Array.from(b).length);
  let ratio;
  let changed;
  if (longest <= LEVENSHTEIN_MAX_LEN) {
    changed = levenshtein(a, b);
    ratio = changed / longest;
  } else {
    const ta = trigrams(a);
    const tb = trigrams(b);
    let inter = 0;
    for (const t of ta) if (tb.has(t)) inter++;
    const union = ta.size + tb.size - inter;
    ratio = union === 0 ? 0 : 1 - inter / union;
    changed = Math.round(ratio * longest);
  }
  if (changed < MIN_CHANGED_CHARS || ratio < MIN_CHANGE_RATIO) {
    return {
      ok: false,
      ratio,
      reason: `แก้ไขน้อยเกินไป (เปลี่ยนไป ${Math.round(ratio * 100)}% ต้องอย่างน้อย ${Math.round(MIN_CHANGE_RATIO * 100)}%)`,
    };
  }
  return { ok: true, ratio, reason: 'แก้ไขเนื้อหาแล้ว' };
}

/** โพสต์ถูกซ่อนอยู่ ณ เวลา [nowMs] หรือไม่ (hiddenUntil = null คือซ่อนจนกว่าจะแก้ไข) */
function isHiddenNow(data, nowMs = Date.now()) {
  if (!data || data.hidden !== true) return false;
  const until = data.hiddenUntil;
  if (until == null) return true;
  const ms = typeof until.toMillis === 'function' ? until.toMillis() : Number(until);
  return ms > nowMs;
}

module.exports = {
  REPORT_HIDE_THRESHOLD,
  ACTIVE_REPORT_STATUSES,
  MIN_CHANGE_RATIO,
  MIN_CHANGED_CHARS,
  normalizeText,
  levenshtein,
  evaluateEdit,
  isHiddenNow,
};
