import test from 'node:test';
import assert from 'node:assert/strict';
import { supportedLocale, translate } from '../src/i18n.mjs';
import { englishCopy } from '../src/i18n-copy.mjs';

test('Arabic is the default and English preserves technical/user values', () => {
  assert.equal(supportedLocale(null), 'ar');
  assert.equal(supportedLocale('fr'), 'ar');
  assert.equal(translate('اختر صورة', 'ar'), 'اختر صورة');
  assert.equal(translate('اختر صورة', 'en'), 'Choose an image');
  for (const value of ['REVIEW_REQUIRED','UNCONFIRMED','private-image.jpg','صورة خاصة.jpg','0_Takbir']) assert.equal(translate(value,'en'),value);
});
test('Only display copy changes in composed model messages', () => {
  assert.equal(translate('وضوح الجسم: 0.982 · الاستعادة: standard · 821 ms','en'),'Body visibility: 0.982 · Recovery: standard · 821 ms');
  assert.equal(translate('تعذر فتح الكاميرا: NotAllowedError','en'),'Could not open the camera: NotAllowedError');
  assert.equal(translate('الركعة 2','en'),'Rakah 2');
});
test('Every translated template retains exactly the original placeholders', () => {
  const placeholders = value => [...value.matchAll(/\{\d+\}/g)].map(match=>match[0]).sort();
  for (const [source,translated] of Object.entries(englishCopy)) assert.deepEqual(placeholders(translated),placeholders(source),source);
});
