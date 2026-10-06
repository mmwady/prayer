import { englishCopy } from './i18n-copy.mjs';

export const supportedLocale = value => value === 'en' ? 'en' : 'ar';
const patterns = Object.entries(englishCopy).filter(([source]) => /\{\d+\}/.test(source)).map(([source, translated]) => {
  const slots = [], parts = []; let offset = 0;
  for (const match of source.matchAll(/\{(\d+)\}/g)) {
    parts.push(source.slice(offset, match.index).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), '([\\s\\S]*?)');
    slots.push(match[1]); offset = match.index + match[0].length;
  }
  parts.push(source.slice(offset).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return { pattern: new RegExp('^' + parts.join('') + '$'), translated, slots, length: source.replace(/\{\d+\}/g, '').length };
}).sort((a,b) => b.length - a.length);

// Display text only. The original recognition code, result objects, form values,
// downloaded JSON and session storage never pass through this adapter.
export function translate(source, language) {
  if (supportedLocale(language) === 'ar') return source;
  if (Object.hasOwn(englishCopy, source)) return englishCopy[source];
  for (const {pattern, translated, slots} of patterns) {
    const match = source.match(pattern);
    if (match) return translated.replace(/\{(\d+)\}/g, (_, index) => match[slots.indexOf(index) + 1]);
  }
  // Results compose known posture labels with untranslated technical values.
  for (const separator of [' · ', '\n']) {
    if (source.includes(separator)) return source.split(separator).map(part => translate(part, language)).join(separator);
  }
  return source;
}

export function installLocalization(document, host = window) {
  let language = supportedLocale(new URL(host.location.href).searchParams.get('lang'));
  const originals = new WeakMap();
  const excluded = 'script,style,pre,code,textarea,input,[contenteditable="true"],[data-iqtadi-raw]';
  function text(node) {
    if (node.parentElement?.closest(excluded)) return;
    const previous = originals.get(node);
    const source = previous && node.data === previous.rendered ? previous.source : node.data;
    const rendered = translate(source, language);
    originals.set(node, {source, rendered});
    if (node.data !== rendered) node.data = rendered;
  }
  function scan(root) {
    if (root.nodeType === 3) { text(root); return; }
    const walker = document.createTreeWalker(root, 4);
    while (walker.nextNode()) text(walker.currentNode);
    const elements = root.querySelectorAll?.('[title],[alt],[aria-label]') ?? [];
    for (const element of elements) {
      if (element.closest(excluded)) continue;
      for (const attribute of ['title','alt','aria-label']) {
        const node = element.getAttributeNode(attribute);
        if (!node) continue;
        const previous = originals.get(node);
        const source = previous && node.value === previous.rendered ? previous.source : node.value;
        const rendered = translate(source, language);
        originals.set(node, {source, rendered});
        if (node.value !== rendered) node.value = rendered;
      }
    }
  }
  function render() {
    document.documentElement.lang = language;
    document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr';
    scan(document.documentElement);
  }
  render();
  const observer = new host.MutationObserver(records => {
    for (const record of records) {
      if (record.type === 'characterData') text(record.target);
      else if (record.type === 'childList') for (const node of record.addedNodes) scan(node);
      else scan(record.target.parentElement ?? document.documentElement);
    }
  });
  observer.observe(document.documentElement, {subtree:true, childList:true, characterData:true, attributes:true, attributeFilter:['title','alt','aria-label']});
  host.addEventListener('message', event => {
    if (event.origin !== host.location.origin || event.source !== host.parent || event.data?.type !== 'iqtadi-locale') return;
    language = supportedLocale(event.data.locale); render();
  });
  return observer;
}

if (typeof document !== 'undefined') installLocalization(document);
