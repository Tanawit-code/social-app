import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { FieldPath, getFirestore } from 'firebase-admin/firestore';

const projectId = 'social-app-3569a';
const applyChanges = process.argv.includes('--apply');
const pageSize = 400;

initializeApp({
  credential: applicationDefault(),
  projectId,
});

const db = getFirestore();
let cursor;
let scanned = 0;
let changed = 0;

while (true) {
  let query = db.collection('posts')
    .orderBy(FieldPath.documentId())
    .limit(pageSize);
  if (cursor) query = query.startAfter(cursor);

  const page = await query.get();
  if (page.empty) break;
  scanned += page.size;

  const legacyDocs = page.docs.flatMap((doc) => {
    const data = doc.data();
    const updates = {};
    if (!Object.hasOwn(data, 'audience')) updates.audience = 'public';
    if (!Object.hasOwn(data, 'pageId')) updates.pageId = null;
    return Object.keys(updates).length > 0 ? [{ doc, updates }] : [];
  });
  changed += legacyDocs.length;

  if (applyChanges && legacyDocs.length > 0) {
    const batch = db.batch();
    for (const { doc, updates } of legacyDocs) {
      // Older personal posts predate both audience and explicit pageId fields.
      batch.update(doc.ref, updates);
    }
    await batch.commit();
  }

  cursor = page.docs.at(-1);
  console.log(`${applyChanges ? 'Processed' : 'Would update'} ${scanned} posts; ${changed} legacy posts found.`);
}

console.log(
  applyChanges
    ? `Migration complete: set ${changed} legacy posts to public.`
    : `Dry run complete: ${changed} legacy posts would be set to public. Run with --apply to write changes.`,
);
