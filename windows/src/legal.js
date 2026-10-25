// The Mac app's legal reader (LegalReaderView): the same five documents from docs/legal, bundled into the app so they open
// offline, shown in a dialog with a switcher. The Markdown is turned into DOM nodes with textContent only (never innerHTML),
// so nothing in a document can run as markup.
import terms from '../../docs/legal/TERMS_OF_SERVICE.md?raw';
import privacy from '../../docs/legal/PRIVACY_POLICY.md?raw';
import acceptableUse from '../../docs/legal/ACCEPTABLE_USE_POLICY.md?raw';
import security from '../../docs/legal/SECURITY_AND_DATA_PROTECTION_POLICY.md?raw';
import credits from '../../docs/legal/ACKNOWLEDGEMENTS.md?raw';

export const LEGAL_DOCS = [
  { key: 'TERMS_OF_SERVICE', title: 'Terms of Service', short: 'Terms', text: terms },
  { key: 'PRIVACY_POLICY', title: 'Privacy Policy', short: 'Privacy', text: privacy },
  { key: 'ACCEPTABLE_USE_POLICY', title: 'Acceptable Use Policy', short: 'Acceptable Use', text: acceptableUse },
  { key: 'SECURITY_AND_DATA_PROTECTION_POLICY', title: 'Security & Data Protection Policy', short: 'Security', text: security },
  { key: 'ACKNOWLEDGEMENTS', title: 'Credits & Licenses', short: 'Credits', text: credits },
];

/** The document a link points at: a site address (/terms, /privacy) or a link between the documents ("PRIVACY_POLICY.md"). */
export function legalDocForLink(href) {
  const site = /^https:\/\/locken-app\.vercel\.app\/(terms|privacy)\/?$/.exec(href);
  if (site) return LEGAL_DOCS.find((d) => d.short.toLowerCase() === (site[1] === 'terms' ? 'terms' : 'privacy'));
  const file = href.split('/').pop();
  return LEGAL_DOCS.find((d) => `${d.key}.md` === file);
}

const el = (tag, text, className) => {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  if (className) node.className = className;
  return node;
};

/** **bold**, *italic*, `code` and [text](link), as DOM nodes. Links go to `onLink(href)`; only http(s), mailto and documents work. */
function inline(text, onLink) {
  const out = document.createDocumentFragment();
  const pattern = /\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|\*([^*\n]+)\*/g;
  let last = 0;
  for (let m = pattern.exec(text); m; m = pattern.exec(text)) {
    if (m.index > last) out.append(text.slice(last, m.index));
    if (m[1] != null) out.append(el('strong', m[1]));
    else if (m[2] != null) out.append(el('code', m[2]));
    else if (m[3] != null) {
      const href = m[4];
      if (/^(https?:|mailto:)/.test(href) || legalDocForLink(href)) {
        const link = el('a', m[3], 'link');
        link.href = /^(https?:|mailto:)/.test(href) ? href : '#';
        link.addEventListener('click', (event) => { event.preventDefault(); onLink(href); });
        out.append(link);
      } else out.append(m[3]);
    } else out.append(el('em', m[5]));
    last = pattern.lastIndex;
  }
  if (last < text.length) out.append(text.slice(last));
  return out;
}

const add = (parent, node) => { parent.append(node); return node; };
const cells = (line) => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());

/** The document as a fragment. The first heading is the dialog's title, and "Drafting note" quotes are for editors, not readers. */
export function renderMarkdown(markdown, onLink) {
  const out = document.createDocumentFragment();
  const lines = markdown.split(/\r?\n/);
  let paragraph = [];
  const flush = () => {
    if (paragraph.length) add(out, el('p')).append(inline(paragraph.join(' '), onLink));
    paragraph = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const t = line.trim();
    let m;
    if (!t) flush();
    else if (t === '---') { flush(); out.append(el('hr')); }
    else if ((m = /^(#{1,6})\s+(.*)$/.exec(t))) {
      flush();
      if (m[1].length > 1) add(out, el(m[1].length === 2 ? 'h2' : 'h3')).append(inline(m[2], onLink));
    } else if (t.startsWith('>')) {
      flush();
      const quoted = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) quoted.push(lines[i++].trim().slice(1).trim());
      i--;
      const text = quoted.join(' ');
      if (!text.includes('Drafting note')) add(out, el('blockquote')).append(inline(text, onLink));
    } else if (t.startsWith('|')) {
      flush();
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        const row = cells(lines[i++]);
        if (!row.every((c) => /^:?-{2,}:?$/.test(c))) rows.push(row);
      }
      i--;
      const table = el('table');
      rows.forEach((row, r) => {
        const tr = add(table, el('tr'));
        row.forEach((c) => add(tr, el(r === 0 ? 'th' : 'td')).append(inline(c, onLink)));
      });
      out.append(table);
    } else if ((m = /^(\s*)[-*]\s+(.*)$/.exec(line))) {
      flush();
      const item = add(out, el('p', null, 'bullet'));
      item.style.marginLeft = `${Math.floor(m[1].length / 2) * 18 + 4}px`;
      item.append('• ', inline(m[2], onLink));
    } else if ((m = /^(\d+[.)])\s+(.*)$/.exec(t))) {
      flush();
      const item = add(out, el('p', null, 'bullet'));
      item.append(`${m[1]} `, inline(m[2], onLink));
    } else paragraph.push(t);
  }
  flush();
  return out;
}
