import { expect, test } from '@playwright/test';
import type { AccountProject, AuthSession } from '../../shared/accounts';

test('guest editing and project creation remain available alongside both optional login methods', async ({ page }) => {
  let indexRequests = 0;
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: null, providers: { google: true, github: true } } }));
  await page.route('**/api/projects**', route => { indexRequests++; return route.fulfill({ status: 401, json: { error: 'ログインしてください。' } }); });
  const room = crypto.randomUUID();
  await page.goto(`/?room=${room}`);
  await expect(page.getByText('Live', { exact: true })).toBeVisible({ timeout: 15000 });
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  for (const provider of ['Google', 'GitHub']) {
    const link = page.getByRole('link', { name: `${provider} でログイン` });
    await expect(link).toBeVisible();
    const url = new URL((await link.getAttribute('href'))!, page.url());
    expect(url.pathname).toBe(`/api/auth/login/${provider.toLowerCase()}`);
    expect(url.searchParams.get('returnTo')).toBe(`/?room=${room}&projects=1`);
  }
  await expect(page.getByRole('region', { name: '自分のプロジェクト', exact: true })).toHaveCount(0);
  await page.getByRole('button', { name: 'New project', exact: false }).click();
  await expect(page).not.toHaveURL(new RegExp(room));
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('Untitled project');
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  expect(indexRequests).toBe(0);
});

test('private shortcuts survive removal and reload while collaboration names and guest editing stay independent', async ({ page }) => {
  const room = crypto.randomUUID();
  let session: AuthSession = { user: { id: 'google:example', name: 'Studio friend', provider: 'google' }, providers: { google: true, github: true } };
  const saved = new Map<string, AccountProject>([['another-private-room', { roomId: 'another-private-room', name: 'Earlier work', updatedAt: Date.now() - 86400000 }]]);
  const dismissed = new Set<string>();
  await page.addInitScript(() => { if (!localStorage.getItem('poietra-user-name')) localStorage.setItem('poietra-user-name', 'Workshop friend'); });
  let puts = 0;
  await page.route('**/api/auth/session', route => route.fulfill({ json: session }));
  await page.route('**/api/auth/logout', route => { session = { ...session, user: null }; return route.fulfill({ status: 204 }); });
  await page.route('**/api/projects**', async route => {
    if (!session.user) { await route.fulfill({ status: 401, json: { error: 'ログインしてください。' } }); return; }
    const request = route.request(); const path = new URL(request.url()).pathname;
    if (request.method() === 'GET') { await route.fulfill({ json: { projects: [...saved.values()] } }); return; }
    expect(request.headers()['x-poietra-account']).toBe('google:example');
    const id = path.split('/').at(-1)!;
    if (request.method() === 'PUT') {
      puts++;
      if (request.postDataJSON().intent !== 'remember' && dismissed.has(id)) { await route.fulfill({ json: { project: null } }); return; }
      dismissed.delete(id);
      const project = { roomId: id, name: request.postDataJSON().name, updatedAt: Date.now() };
      saved.set(id, project); await route.fulfill({ json: { project } });
    } else { saved.delete(id); dismissed.add(id); await route.fulfill({ status: 204 }); }
  });
  await page.goto(`/?room=${room}&projects=1`);
  await expect(page.getByRole('dialog', { name: 'Projects' })).toBeVisible();
  await expect(page.getByText('Studio friend', { exact: true })).toBeVisible();
  await expect.poll(() => saved.get(room)?.name).toBe('A little motion');
  await expect(page.getByRole('link', { name: /Earlier work/ })).toBeVisible();
  await expect(page.getByRole('button', { name: '一覧に追加済み', exact: true })).toBeDisabled();
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('button', { name: '共同編集の表示名と共有', exact: true }).click();
  const displayName = page.getByRole('textbox', { name: '共同編集での表示名', exact: true });
  await expect(displayName).toHaveValue('Workshop friend');
  await displayName.fill('Collaborator name');
  await displayName.blur();
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('A new title');
  await expect.poll(() => saved.get(room)?.name).toBe('A new title');
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await page.getByRole('button', { name: 'A new title を自分の一覧から外す', exact: true }).click();
  await expect.poll(() => saved.has(room)).toBe(false);
  await expect(page.getByRole('status').filter({ hasText: '自分の一覧から外しました' })).toBeVisible();
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('Still shared');
  const revisit = page.waitForResponse(response => response.url().endsWith('/api/projects/' + room) && response.request().method() === 'PUT');
  await page.reload();
  expect(await (await revisit).json()).toEqual({ project: null });
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await expect(page.getByText('Studio friend', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: /Still shared/ })).toHaveCount(0);
  await page.getByRole('button', { name: 'このプロジェクトを一覧に追加', exact: true }).click();
  await expect.poll(() => saved.get(room)?.name).toBe('Still shared');
  await page.getByRole('button', { name: 'ログアウト', exact: true }).click();
  await expect(page.getByRole('region', { name: '自分のプロジェクト', exact: true })).toHaveCount(0);
  await expect(page.getByRole('link', { name: 'Google でログイン' })).toBeVisible();
  const before = puts;
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('button', { name: '共同編集の表示名と共有', exact: true }).click();
  await expect(displayName).toHaveValue('Collaborator name');
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('Edited as guest');
  await page.waitForTimeout(800);
  expect(puts).toBe(before);
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await expect(page).toHaveURL(new RegExp(room));
});

test('reaching the private list limit keeps existing shortcuts and the signed-in session visible', async ({ page }) => {
  const room = crypto.randomUUID();
  const existing = { roomId: 'existing-private-room', name: 'Earlier work', updatedAt: Date.now() };
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: { id: 'google:alice', name: 'Alice', provider: 'google' }, providers: { google: true, github: true } } }));
  await page.route('**/api/projects**', route => {
    const request = route.request();
    if (request.method() === 'GET') return route.fulfill({ json: { projects: [existing] } });
    if (request.postDataJSON().intent === 'visit') return route.fulfill({ json: { project: null } });
    return route.fulfill({ status: 409, json: { code: 'project_limit', error: '一覧は 500 件まで保存できます。' } });
  });
  await page.goto(`/?room=${room}&projects=1`);
  const add = page.getByRole('button', { name: 'このプロジェクトを一覧に追加', exact: true });
  await expect(add).toBeEnabled();
  await add.click();
  await expect(page.getByRole('alert')).toContainText('500 件');
  await expect(page.getByRole('link', { name: /Earlier work/ })).toBeVisible();
  await expect(page.getByText('Alice', { exact: true })).toBeVisible();
});

test('a session lookup failure stays distinguishable from guest mode and can be retried', async ({ page }) => {
  let failed = true;
  await page.route('**/api/auth/session', route => failed
    ? route.fulfill({ status: 503, json: { error: '接続を再確認してください。' } })
    : route.fulfill({ json: { user: null, providers: { google: true, github: true } } }));
  await page.goto(`/?room=${crypto.randomUUID()}&projects=1`);
  await expect(page.getByRole('heading', { name: 'ログイン状態を確認できませんでした' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'ゲストで編集中' })).toHaveCount(0);
  failed = false;
  await page.getByRole('button', { name: '再試行', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'ゲストで編集中' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'GitHub でログイン', exact: true })).toBeVisible();
});

test('returning to a tab refreshes changes to the same account list made elsewhere', async ({ page }) => {
  let visible = true;
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: { id: 'google:alice', name: 'Alice', provider: 'google' }, providers: { google: true, github: true } } }));
  await page.route('**/api/projects**', route => route.fulfill({ json: route.request().method() === 'GET'
    ? { projects: visible ? [{ roomId: 'elsewhere-private-room', name: 'Work from another device', updatedAt: Date.now() }] : [] }
    : { project: null } }));
  await page.goto(`/?room=${crypto.randomUUID()}&projects=1`);
  const shortcut = page.getByRole('link', { name: /Work from another device/ });
  await expect(shortcut).toBeVisible();
  visible = false;
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect(shortcut).toHaveCount(0);
  await expect(page.getByText('Alice', { exact: true })).toBeVisible();
});

test('a skipped visit recovers a slow list read and a shortcut restored on another device resumes title refreshes', async ({ page }) => {
  const room = crypto.randomUUID();
  let lists = 0, listed = false, title = 'Restored elsewhere', releaseFirst!: () => void;
  const firstList = new Promise<void>(resolve => { releaseFirst = resolve; });
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: { id: 'github:alice', name: 'Alice', provider: 'github' }, providers: { google: false, github: true } } }));
  await page.route('**/api/projects**', async route => {
    if (route.request().method() === 'GET') {
      if (++lists === 1) await firstList;
      return route.fulfill({ json: { projects: [
        { roomId: 'unrelated-private-room', name: 'Unrelated work', updatedAt: 1 },
        ...(listed ? [{ roomId: room, name: title, updatedAt: 2 }] : []),
      ] } });
    }
    title = route.request().postDataJSON().name;
    return route.fulfill({ json: { project: listed ? { roomId: room, name: title, updatedAt: 3 } : null } });
  });
  try {
    await page.goto(`/?room=${room}&projects=1`);
    await expect(page.getByRole('link', { name: /Unrelated work/ })).toBeVisible();
    listed = true;
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await expect(page.getByRole('button', { name: '一覧に追加済み', exact: true })).toBeDisabled();
    await page.getByRole('button', { name: '閉じる', exact: true }).click();
    await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('Title after restoration');
    await expect.poll(() => title).toBe('Title after restoration');
  } finally { releaseFirst(); }
});

test('a cancelled login returns to the same guest project with an actionable message', async ({ page }) => {
  const room = crypto.randomUUID();
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: null, providers: { google: true, github: true } } }));
  await page.goto(`/?room=${room}&projects=1&auth_error=denied`);
  await expect(page.getByRole('dialog', { name: 'Projects' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('ログインをキャンセルしました');
  await expect(page).toHaveURL(new RegExp(`room=${room}$`));
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await expect(page.getByText('Live', { exact: true })).toBeVisible();
  await page.getByRole('textbox', { name: 'Project name', exact: true }).fill('Guest continues');
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('Guest continues');
});

for (const delayedMethod of ['GET', 'PUT']) test(`a delayed ${delayedMethod} response from the previous account cannot replace the current account's projects`, async ({ page }) => {
  const room = crypto.randomUUID();
  let account = 'google:alice';
  const writes: string[] = [];
  let bobLists = 0, releaseBobList!: () => void;
  const bobRefresh = new Promise<void>(resolve => { releaseBobList = resolve; });
  await page.addInitScript(method => {
    const original = window.fetch.bind(window);
    let release!: () => void;
    const paused = new Promise<void>(resolve => { release = resolve; });
    Object.assign(window, { releaseAccountResponse: release, accountResponsePaused: false });
    window.fetch = async (input, init) => {
      const response = await original(input, init);
      const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, location.href);
      if (url.pathname.startsWith('/api/projects') && (init?.method ?? 'GET') === method && new Headers(init?.headers).get('X-Poietra-Account') === 'google:alice') {
        const json = response.json.bind(response);
        // Reproduce a response already received when abort happens: JSON work
        // can finish later even though the originating account has gone away.
        response.json = async () => { const value = await json(); Object.assign(window, { accountResponsePaused: true }); await paused; return value; };
      }
      return response;
    };
  }, delayedMethod);
  await page.route('**/api/auth/session', route => route.fulfill({ json: { user: { id: account, name: account === 'google:alice' ? 'Alice' : 'Bob', provider: 'google' }, providers: { google: true, github: true } } }));
  await page.route('**/api/projects**', async route => {
    const owner = route.request().headers()['x-poietra-account'];
    const project = { roomId: owner === 'google:alice' ? 'alice-private-room' : 'bob-private-room', name: owner === 'google:alice' ? 'Alice private work' : 'Bob private work', updatedAt: Date.now() };
    if (route.request().method() === 'PUT') { writes.push(owner); return route.fulfill({ json: { project } }); }
    if (owner === 'google:bob' && ++bobLists > 1) await bobRefresh;
    return route.fulfill({ json: { projects: [project] } });
  });
  await page.goto(`/?room=${room}&projects=1`);
  await expect(page.getByText('Alice', { exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => (window as unknown as { accountResponsePaused: boolean }).accountResponsePaused)).toBe(true);
  account = 'google:bob';
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect(page.getByText('Bob', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: /Bob private work/ })).toBeVisible();
  await expect.poll(() => writes.includes('google:bob')).toBe(true);
  // Hold the refresh after PUT so optimistic reconciliation is observable.
  await expect.poll(() => bobLists).toBeGreaterThan(1);
  try { await expect(page.getByRole('link', { name: /Bob private work/ })).toHaveCount(1); }
  finally { releaseBobList(); }
  await page.evaluate(() => (window as unknown as { releaseAccountResponse(): void }).releaseAccountResponse());
  await expect(page.getByRole('link', { name: /Alice private work/ })).toHaveCount(0);
  await expect(page.getByRole('link', { name: /Bob private work/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'ログアウト', exact: true })).toBeEnabled();
});

test('private projects can be searched and sorted locally while refresh retains the chosen view', async ({ page }) => {
  let projects: AccountProject[] = [
    { roomId: 'zebra-room', name: 'Zebra', updatedAt: 1 },
    { roomId: 'alpha-room', name: 'alpha', updatedAt: 2 },
    { roomId: 'spring-room', name: '春の動画', updatedAt: 3 },
  ];
  let writes = 0;
  await page.route('**/api/auth/session', route => route.fulfill({ json: {
    user: { id: 'google:alice', name: 'Alice', provider: 'google' }, providers: { google: true, github: true },
  } }));
  await page.route('**/api/projects**', route => {
    if (route.request().method() === 'GET') return route.fulfill({ json: { projects } });
    writes++;
    expect(route.request().postDataJSON().intent).toBe('visit');
    return route.fulfill({ json: { project: null } });
  });
  await page.goto(`/?room=${crypto.randomUUID()}&projects=1`);
  const list = page.getByRole('region', { name: '自分のプロジェクト', exact: true });
  const titles = list.locator('.saved-project-title strong');
  await expect(titles).toHaveText(['春の動画', 'alpha', 'Zebra']);
  await expect.poll(() => writes).toBe(1);
  await list.getByRole('combobox', { name: 'プロジェクトの並び順' }).selectOption('name');
  await expect(titles).toHaveText(['alpha', 'Zebra', '春の動画']);
  const search = list.getByRole('searchbox', { name: 'プロジェクトを検索' });
  await search.fill('  ALPHA  ');
  await expect(titles).toHaveText(['alpha']);
  await expect(list.getByRole('status').filter({ hasText: '1 / 3 件' })).toBeVisible();
  await search.fill('動画');
  await expect(titles).toHaveText(['春の動画']);
  await search.fill('missing');
  await expect(titles).toHaveCount(0);
  await expect(list.getByText('一致するプロジェクトがありません。検索する名前を変えてください。')).toBeVisible();
  await search.fill('alpha');
  projects = [...projects, { roomId: 'another-alpha', name: 'alpha follow-up', updatedAt: 4 }];
  await list.getByRole('button', { name: '一覧を更新', exact: true }).click();
  await expect(titles).toHaveText(['alpha', 'alpha follow-up']);
  await expect(search).toHaveValue('alpha');
  await expect(list.getByRole('combobox')).toHaveValue('name');
  expect(writes).toBe(1);
});

test('failed list reads remain errors and retry preserves already loaded shortcuts', async ({ page }) => {
  let failed = true;
  await page.route('**/api/auth/session', route => route.fulfill({ json: {
    user: { id: 'google:alice', name: 'Alice', provider: 'google' }, providers: { google: true, github: true },
  } }));
  await page.route('**/api/projects**', route => {
    if (route.request().method() !== 'GET') return route.fulfill({ json: { project: null } });
    return failed
      ? route.fulfill({ status: 503, json: { error: '一覧を読み込めませんでした。' } })
      : route.fulfill({ json: { projects: [{ roomId: 'earlier-room', name: 'Earlier work', updatedAt: 1 }] } });
  });
  await page.goto(`/?room=${crypto.randomUUID()}&projects=1`);
  const list = page.getByRole('region', { name: '自分のプロジェクト', exact: true });
  await expect(list.getByRole('alert')).toContainText('一覧を読み込めませんでした');
  await expect(list.getByText(/^一覧は空です/)).toHaveCount(0);
  failed = false;
  await list.getByRole('button', { name: '一覧を更新', exact: true }).click();
  const shortcut = list.getByRole('link', { name: /Earlier work/ });
  await expect(shortcut).toBeVisible();
  await expect(list.getByRole('alert')).toHaveCount(0);
  failed = true;
  await list.getByRole('button', { name: '一覧を更新', exact: true }).click();
  await expect(list.getByRole('alert')).toBeVisible();
  await expect(shortcut).toBeVisible();
  failed = false;
  await list.getByRole('button', { name: '一覧を更新', exact: true }).click();
  await expect(list.getByRole('alert')).toHaveCount(0);
  await expect(shortcut).toBeVisible();
});

test('removing a shortcut offers a retryable restore scoped to the current account', async ({ page }) => {
  const room = crypto.randomUUID();
  let account = 'google:alice', listed = true, rejectRestore = true, remembered = 0;
  await page.route('**/api/auth/session', route => route.fulfill({ json: {
    user: { id: account, name: account === 'google:alice' ? 'Alice' : 'Bob', provider: 'google' }, providers: { google: true, github: true },
  } }));
  await page.route('**/api/projects**', route => {
    const request = route.request();
    const project = { roomId: 'earlier-room', name: 'Earlier work', updatedAt: 1 };
    if (request.method() === 'GET') return route.fulfill({ json: { projects: account === 'google:alice' && listed ? [project] : [] } });
    if (request.method() === 'DELETE') {
      expect(request.headers()['x-poietra-account']).toBe('google:alice');
      listed = false;
      return route.fulfill({ status: 204 });
    }
    if (request.postDataJSON().intent === 'visit') return route.fulfill({ json: { project: null } });
    expect(request.headers()['x-poietra-account']).toBe('google:alice');
    expect(request.postDataJSON()).toEqual({ intent: 'remember', name: 'Earlier work' });
    expect(new URL(request.url()).pathname).toBe('/api/projects/earlier-room');
    remembered++;
    if (rejectRestore) return route.fulfill({ status: 503, json: { error: '一覧への追加を再試行してください。' } });
    listed = true;
    return route.fulfill({ json: { project } });
  });
  await page.goto(`/?room=${room}&projects=1`);
  const list = page.getByRole('region', { name: '自分のプロジェクト', exact: true });
  const remove = list.getByRole('button', { name: 'Earlier work を自分の一覧から外す', exact: true });
  const restore = list.getByRole('button', { name: 'Earlier work を自分の一覧に戻す', exact: true });
  await remove.click();
  await expect(list.getByRole('link', { name: /Earlier work/ })).toHaveCount(0);
  await restore.click();
  await expect(page.getByRole('alert')).toContainText('一覧への追加を再試行');
  await expect(restore).toBeEnabled();
  rejectRestore = false;
  await restore.click();
  await expect(list.getByRole('link', { name: /Earlier work/ })).toBeVisible();
  await expect(restore).toHaveCount(0);
  expect(remembered).toBe(2);
  await expect(page).toHaveURL(new RegExp(room));
  await page.getByRole('button', { name: '閉じる', exact: true }).click();
  await expect(page.getByRole('textbox', { name: 'Project name', exact: true })).toHaveValue('A little motion');
  await page.getByRole('button', { name: 'プロジェクトを開く', exact: true }).click();
  await remove.click();
  await expect(restore).toBeEnabled();
  await list.getByRole('searchbox').fill('private query');
  await list.getByRole('combobox').selectOption('name');
  account = 'google:bob';
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect(page.getByText('Bob', { exact: true })).toBeVisible();
  await expect(restore).toHaveCount(0);
  await expect(list.getByRole('searchbox')).toHaveValue('');
  await expect(list.getByRole('combobox')).toHaveValue('recent');
  await expect(list.getByRole('link', { name: /Earlier work/ })).toHaveCount(0);
  expect(remembered).toBe(2);
});
