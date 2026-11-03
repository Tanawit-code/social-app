const test = require('node:test');
const assert = require('node:assert');
const { evaluateEdit, isHiddenNow, normalizeText, REPORT_HIDE_THRESHOLD } = require('./moderation_logic');

test('ค่าเริ่มต้น: ซ่อนเมื่อมีผู้รายงาน 3 คนขึ้นไป (มากกว่า 2)', () => {
  assert.strictEqual(REPORT_HIDE_THRESHOLD, 3);
});

test('ไม่เปลี่ยนอะไรเลย -> ไม่ผ่าน', () => {
  assert.strictEqual(evaluateEdit('สวัสดีทุกคน', 'สวัสดีทุกคน').ok, false);
});

test('แก้แค่ช่องว่าง/เครื่องหมาย/ตัวพิมพ์ -> ไม่ผ่าน', () => {
  assert.strictEqual(evaluateEdit('Hello world!', ' hello   WORLD ... ').ok, false);
});

test('เติม 1 ตัวอักษรในข้อความยาว -> ไม่ผ่าน', () => {
  const t = 'นี่คือโพสต์ที่มีเนื้อหาไม่เหมาะสมและยาวพอสมควรเพื่อทดสอบ';
  assert.strictEqual(evaluateEdit(t, t + 'ๆ').ok, false);
});

test('เขียนใหม่ส่วนใหญ่ -> ผ่าน', () => {
  assert.strictEqual(
    evaluateEdit('ไอ้โง่ ไปตายซะ ไม่มีใครอยากเห็นหน้า', 'ขอโทษที่พูดแรงไป วันนี้อารมณ์ไม่ดี').ok,
    true,
  );
});

test('ลบข้อความทั้งหมด: ผ่านเฉพาะโพสต์ที่มีสื่อ', () => {
  assert.strictEqual(evaluateEdit('ข้อความไม่ดี', '', { hasMedia: true }).ok, true);
  assert.strictEqual(evaluateEdit('ข้อความไม่ดี', '').ok, false);
});

test('ข้อความยาวมาก ใช้ 3-gram ได้และไม่ช้า', () => {
  const a = 'abcdefghij'.repeat(500);
  const b = 'zyxwvutsrq'.repeat(500);
  assert.strictEqual(evaluateEdit(a, b).ok, true);
  assert.strictEqual(evaluateEdit(a, a + 'x').ok, false);
});

test('isHiddenNow', () => {
  const now = 1_000_000;
  assert.strictEqual(isHiddenNow({ hidden: false }, now), false);
  assert.strictEqual(isHiddenNow({ hidden: true }, now), true); // จนกว่าจะแก้ไข
  assert.strictEqual(isHiddenNow({ hidden: true, hiddenUntil: now + 1 }, now), true);
  assert.strictEqual(isHiddenNow({ hidden: true, hiddenUntil: now - 1 }, now), false);
});

test('normalizeText ตัด zero-width และเครื่องหมาย', () => {
  assert.strictEqual(normalizeText('A​ b-c!'), 'abc');
});
