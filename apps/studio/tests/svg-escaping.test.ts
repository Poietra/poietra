import { expect, it } from 'vitest';
import { toUSVString } from 'node:util';
import { escapeXml } from '../src/engine/rendering/svg';

const entities: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' };
const reference = (value: string) => toUSVString(value).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, '').replace(/[&<>"']/g, value => entities[value]);

it('matches the XML character rules across every UTF-16 code unit', () => {
  // Separators force every surrogate to be isolated; valid pairs are checked below.
  const units = Array.from({ length: 65536 }, (_, code) => String.fromCharCode(code) + 'x').join('');
  expect(escapeXml(units)).toBe(reference(units));
  for (const value of ['\ud800\udc00', '\udbff\udfff', '\ud800\ud800\udc00', '\udc00\ud800', '\ud800', '\udfff', '😀&\ud800\udc00<\udbff\udfff', '\u0000\t\n\r\u0001']) expect(escapeXml(value)).toBe(reference(value));
});

it('preserves long unchanged data and replaces only the surrounding special spans', () => {
  const source = 'data:image/png;base64,' + 'A'.repeat(1048576);
  expect(escapeXml(source)).toBe(source);
  for (const value of [`&${source}`, `${source}<`, `${source}'${source}`, `😀${source}\ud800${source}\u0000`, '日本語<&"\'>😀'.repeat(1000)]) expect(escapeXml(value)).toBe(reference(value));
});
