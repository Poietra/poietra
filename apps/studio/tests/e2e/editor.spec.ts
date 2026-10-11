import { expect, test, type Page } from '@playwright/test';
import { chooseOption } from './select';

async function open(page: Page, room: string) { await page.goto(`/?room=${room}`); await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 }); await expect(page.locator('[data-testid="stage-main"] [data-object-id="circle"]')).toBeVisible(); }
async function selectCircle(page: Page) { await page.getByRole('button', { name: 'Circle', exact: true }).click(); }
async function x(page: Page) {
  const surface = await page.getByTestId('stage-main').boundingBox();
  const object = await page.locator('[data-testid="stage-main"] [data-object-id="circle"]').boundingBox();
  if (!surface || !object) return -1;
  return Math.round((object.x + object.width / 2 - surface.x) / surface.width * 1280 * 100) / 100;
}

test('a property update reaches another browser; undo preserves the collaborator’s color', async ({ browser }) => {
  const first = await browser.newContext(); const second = await browser.newContext();
  const alice = await first.newPage(); const bob = await second.newPage(); const room = crypto.randomUUID();
  await Promise.all([open(alice, room), open(bob, room)]);
  await selectCircle(alice); await selectCircle(bob);
  await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).fill('320');
  await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).press('Tab');
  await expect.poll(() => x(bob)).toBe(320);
  await bob.getByRole('button', { name: '色 #f4ce55', exact: true }).click();
  await expect(alice.getByRole('textbox', { name: 'Fillのカラーコード' })).toHaveValue('F4CE55');
  await alice.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect.poll(() => x(bob)).toBe(245);
  await expect(bob.getByRole('textbox', { name: 'Fillのカラーコード' })).toHaveValue('F4CE55');
  await first.close(); await second.close();
});

test('composition state stays independent and an unchanged focused field does not overwrite remote changes', async ({ browser }) => {
  const first = await browser.newContext(); const second = await browser.newContext();
  const alice = await first.newPage(); const bob = await second.newPage(); const room = crypto.randomUUID();
  await Promise.all([open(alice, room), open(bob, room)]);
  await selectCircle(alice); await selectCircle(bob);
  await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).focus();
  await bob.getByRole('spinbutton', { name: 'Position X', exact: true }).fill('350'); await bob.getByRole('spinbutton', { name: 'Position X', exact: true }).press('Tab');
  await expect.poll(() => x(alice)).toBe(350);
  await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).press('Tab');
  await expect.poll(() => x(alice)).toBe(350);
  await alice.getByRole('button', { name: 'Composition 2', exact: true }).click();
  await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).fill('900'); await alice.getByRole('spinbutton', { name: 'Position X', exact: true }).press('Tab');
  await expect.poll(() => x(alice)).toBe(900); await expect.poll(() => x(bob)).toBe(350);
  await first.close(); await second.close();
});

test('scrubbing displays the evaluated frame while paused', async ({ page }) => {
  await open(page, crypto.randomUUID());
  await page.getByRole('slider', { name: '再生位置', exact: true }).evaluate(element => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(element, '1300');
    element.dispatchEvent(new Event('input', { bubbles: true }));
    element.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await expect.poll(() => x(page)).toBeCloseTo(588.75, 1);
  await expect(page.getByRole('button', { name: 'シーンを再生', exact: true })).toBeVisible();
});

test('the transition editor changes timing and lets the user drag a Bézier control point', async ({ page }) => {
  await open(page, crypto.randomUUID()); await selectCircle(page);
  await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
  await page.getByRole('spinbutton', { name: 'Animation start', exact: true }).fill('100'); await page.getByRole('spinbutton', { name: 'Animation start', exact: true }).press('Tab');
  await expect(page.getByRole('button', { name: 'Circle Move: 100–700 ms', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Edit Bézier path', exact: true }).click();
  const handle = page.locator('[data-path-handle="c1"]'); const before = await handle.boundingBox();
  await page.mouse.move(before!.x+before!.width/2,before!.y+before!.height/2); await page.mouse.down(); await page.mouse.move(before!.x+before!.width/2,before!.y-30,{steps:4}); await page.mouse.up();
  await expect.poll(async () => (await handle.boundingBox())!.y).toBeLessThan(before!.y-20);
});

test('colour popups share the menu surface and support RGB, hue, keyboard and a single drag Undo', async ({ page }) => {
  await open(page, crypto.randomUUID()); await selectCircle(page);
  const trigger = page.getByRole('button', { name: 'Fillの色を選択', exact: true });
  const hex = page.getByRole('textbox', { name: 'Fillのカラーコード', exact: true });
  await trigger.focus(); await trigger.press('Delete');
  await expect(page.locator('[data-layer-id="circle"]')).toBeVisible();
  await trigger.click();
  const popup = page.getByRole('dialog', { name: 'Fillの色を選択', exact: true });
  await expect(popup).toBeVisible();
  await expect(popup).toHaveCSS('background-color', 'rgb(26, 26, 35)');
  await expect(page.locator('input[type=color]')).toHaveCount(0);
  for (const [channel, value] of [['R', '255'], ['G', '0'], ['B', '0']]) {
    const input = popup.getByRole('spinbutton', { name: `Fill ${channel}`, exact: true });
    await input.fill(value); await input.press('Tab');
  }
  await expect(hex).toHaveValue('FF0000');
  await expect(popup).toBeHidden(); // Tab out of the final field dismisses the palette.
  await trigger.click();
  const hue = popup.getByRole('slider', { name: 'Fillの色相', exact: true });
  await hue.fill('120');
  await expect(hex).toHaveValue('00FF00');
  const plane = popup.getByRole('slider', { name: 'Fillの彩度と明度', exact: true });
  const box = (await plane.boundingBox())!;
  await plane.click({ position: { x: box.width / 2, y: box.height / 2 } });
  await expect(hex).toHaveValue('408040');
  await plane.press('ArrowUp');
  await expect(hex).toHaveValue('418241');
  const before = await hex.inputValue();
  await page.mouse.move(box.x + box.width * .6, box.y + box.height * .4);
  await page.mouse.down();
  await page.waitForTimeout(600); // Exceeds ordinary Undo capture; the drag stays one action.
  await page.mouse.move(box.x + box.width * .8, box.y + box.height * .2, { steps: 5 });
  await page.mouse.up();
  await expect(hex).not.toHaveValue(before);
  await page.keyboard.press('Escape');
  await expect(popup).toBeHidden(); await expect(trigger).toBeFocused();
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(hex).toHaveValue(before);
  await trigger.click();
  await page.screenshot({ path: test.info().outputPath('colour-picker.png'), fullPage: true });
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Strokeの色を選択', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Strokeの色を選択', exact: true })).toBeVisible();
});

test('a cancelled colour drag retains a peer colour and a peer lock closes the popup', async ({ page, browser }) => {
  await open(page, crypto.randomUUID()); await selectCircle(page);
  const context = await browser.newContext(); const peer = await context.newPage();
  try {
    await peer.goto(page.url()); await expect(peer.getByText('Live', { exact: true })).toBeVisible(); await selectCircle(peer);
    const hex = page.getByRole('textbox', { name: 'Fillのカラーコード', exact: true });
    const original = await hex.inputValue();
    const trigger = page.getByRole('button', { name: 'Fillの色を選択', exact: true });
    await trigger.click();
    const plane = page.getByRole('slider', { name: 'Fillの彩度と明度', exact: true });
    const box = (await plane.boundingBox())!;
    await page.mouse.move(box.x + box.width * .5, box.y + box.height * .5); await page.mouse.down();
    await expect(hex).not.toHaveValue(original);
    await page.keyboard.press('Escape'); await page.mouse.up();
    await expect(hex).toHaveValue(original);
    await trigger.click();
    await page.mouse.move(box.x + box.width * .5, box.y + box.height * .5); await page.mouse.down();
    await page.evaluate(() => window.dispatchEvent(new Event('blur'))); await page.mouse.up();
    await expect(hex).toHaveValue(original);
    await page.mouse.move(box.x + box.width * .3, box.y + box.height * .3); await page.mouse.down();
    await peer.getByRole('button', { name: '色 #f4ce55', exact: true }).click();
    await expect(hex).toHaveValue('F4CE55');
    await page.mouse.move(box.x + box.width * .8, box.y + box.height * .2); await page.mouse.up();
    await expect(hex).toHaveValue('F4CE55');
    await peer.getByRole('button', { name: 'ロック', exact: true }).click();
    await expect(page.getByRole('dialog', { name: 'Fillの色を選択', exact: true })).toBeHidden();
    await expect(trigger).toBeDisabled();
    await peer.getByRole('button', { name: 'ロック解除', exact: true }).click();
    await expect(trigger).toBeEnabled();
    await expect(page.getByRole('dialog', { name: 'Fillの色を選択', exact: true })).toBeHidden();
  } finally { await context.close(); }
});

test('closing the colour popup suppresses late eyedropper completion', async ({ page }) => {
  await page.addInitScript(() => {
    Object.assign(window, { EyeDropper: class {
      open() { return new Promise(resolve => Object.assign(window, { finishColourPick: resolve })); }
    } });
  });
  await open(page, crypto.randomUUID()); await selectCircle(page);
  const trigger = page.getByRole('button', { name: 'Fillの色を選択', exact: true });
  const hex = page.getByRole('textbox', { name: 'Fillのカラーコード', exact: true });
  await trigger.click(); await page.getByRole('button', { name: '画面から色を取得', exact: true }).click();
  await page.evaluate(() => (window as any).finishColourPick({ sRGBHex: '#123456' }));
  await expect(hex).toHaveValue('123456');
  await page.getByRole('button', { name: '画面から色を取得', exact: true }).click();
  await page.keyboard.press('Escape');
  await page.evaluate(() => (window as any).finishColourPick({ sRGBHex: '#abcdef' }));
  await trigger.click();
  await expect(hex).toHaveValue('123456');
  await expect(page.getByRole('button', { name: '画面から色を取得', exact: true })).toBeEnabled();
});

test('the shared colour popup edits background and intermediate keyframe colours', async ({ page }) => {
  await open(page, crypto.randomUUID());
  await page.getByTestId('stage-main').click({ position: { x: 20, y: 20 } });
  const background = page.getByRole('textbox', { name: 'Backgroundのカラーコード', exact: true });
  const before = await background.inputValue();
  await page.getByRole('button', { name: 'Backgroundの色を選択', exact: true }).click();
  const green = page.getByRole('spinbutton', { name: 'Background G', exact: true });
  await green.fill('255'); await green.press('Tab');
  await expect(background).toHaveValue(before.slice(0, 2) + 'FF' + before.slice(4));
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(background).toHaveValue(before);
  await selectCircle(page);
  await page.getByRole('button', { name: 'Transition 800 ms', exact: true }).click();
  await chooseOption(page.getByRole('combobox', { name: 'Animation property', exact: true }), 'fill');
  await page.getByRole('button', { name: '中間点を追加', exact: true }).click();
  const keyframe = page.getByRole('textbox', { name: 'fill keyframe 1 valueのカラーコード', exact: true });
  const initial = await keyframe.inputValue();
  await page.getByRole('button', { name: 'fill keyframe 1 valueの色を選択', exact: true }).click();
  const red = page.getByRole('spinbutton', { name: 'fill keyframe 1 value R', exact: true });
  await red.fill('12'); await red.press('Tab');
  await expect(keyframe).toHaveValue('0C' + initial.slice(2));
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: '元に戻す (⌘Z)', exact: true }).click();
  await expect(keyframe).toHaveValue(initial);
});
