// Run against a local Vite server. All API requests are mocked; no user data is
// read or written. PLAYWRIGHT_MODULE may point to a temporary playwright-core.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const origin = process.env.SYNCBOX_WEB_URL || 'http://127.0.0.1:5173';
const screenshots = process.env.SYNCBOX_SCREENSHOTS;
const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';
const user = { id: 'fixture-owner', username: '测试账号', deviceId: 'fixture-web' };
const device = {
  id: 'fixture-web',
  name: '测试浏览器',
  platform: 'web',
  lastSeenAt: new Date().toISOString(),
};
const pageResult = (items) => ({
  items,
  total: items.length,
  page: 1,
  totalPages: items.length ? 1 : 0,
});

async function fixture(width) {
  const context = await browser.newContext({ viewport: { width, height: 820 } });
  await context.addInitScript(
    ({ user, a }) => {
      sessionStorage.setItem(
        'syncbox-session',
        JSON.stringify({ accessToken: 'fixture-token', user }),
      );
      localStorage.setItem(
        'syncbox.pending-text.v1',
        JSON.stringify([
          {
            clientId: 'old-queue-id',
            conversationId: a,
            content: '旧队列不得补发',
            createdAt: Date.now(),
          },
        ]),
      );
    },
    { user, a },
  );
  const page = await context.newPage();
  page.setDefaultTimeout(6000);
  const state = {
    mode: 'fail',
    sends: [],
    messages: [],
    readFailure: false,
    releaseSend: null,
    releaseB: null,
    bRequested: false,
    errors: [],
  };
  page.on('pageerror', (error) => state.errors.push(error.message));
  const conversations = [
    {
      id: a,
      title: '手动发送测试',
      isPinned: false,
      preview: '',
      messageCount: 0,
      updatedAt: '2026-11-09T04:00:00Z',
    },
    {
      id: b,
      title: '另一会话',
      isPinned: false,
      preview: '',
      messageCount: 0,
      updatedAt: '2026-11-09T04:00:00Z',
    },
  ];
  await page.route('**/api/v1/**', async (route) => {
    const req = route.request(),
      path = new URL(req.url()).pathname.replace('/api/v1', '');
    const json = (body, status = 200) => route.fulfill({ status, json: body });
    if (path === '/auth/me') return json(user);
    if (path === '/devices') return json(req.method() === 'POST' ? device : [device]);
    if (path === '/events')
      return route.fulfill({
        status: 200,
        contentType: 'text/event-stream',
        body: ': heartbeat\n\n',
      });
    if (req.method() === 'POST' && /\/(messages|attachments)$/.test(path)) {
      const file = path.endsWith('/attachments');
      const body = file ? req.postData() : req.postDataJSON();
      const clientId = file ? /name="clientId"\r\n\r\n([^\r]+)/.exec(body)?.[1] : body.clientId;
      state.sends.push({ clientId, path });
      if (state.mode === 'hold' || state.mode === 'cancel') {
        await new Promise((resolve) => {
          state.releaseSend = resolve;
        });
      }
      if (state.mode === 'fail') return json({ message: '服务暂不可用' }, 503);
      const sent = {
        id: `sent-${state.sends.length}`,
        conversationId: a,
        content: file ? '[附件] notes.txt' : body.content,
        createdAt: new Date().toISOString(),
        isStarred: false,
        isRead: false,
        senderDevice: { id: device.id, name: device.name, platform: 'web' },
      };
      state.messages.push(sent);
      if (state.mode === 'read-failure') state.readFailure = true;
      return json(sent, 201);
    }
    if (path.endsWith('/read')) return route.fulfill({ status: 204 });
    if (path === '/conversations')
      return state.readFailure
        ? json({ message: 'read failed' }, 503)
        : json(pageResult(conversations));
    if (path === `/conversations/${b}/messages`) {
      state.bRequested = true;
      if (state.mode === 'hold')
        await new Promise((resolve) => {
          state.releaseB = resolve;
        });
      return json(
        pageResult([
          {
            id: 'b-message',
            content: '另一会话正常加载',
            createdAt: new Date().toISOString(),
            isStarred: false,
          },
        ]),
      );
    }
    if (path.endsWith('/messages'))
      return state.readFailure
        ? json({ message: 'read failed' }, 503)
        : json(pageResult([...state.messages].reverse()));
    throw new Error(`Unexpected API request: ${req.method()} ${path}`);
  });
  await page.goto(origin);
  await page.getByRole('button', { name: /^手动发送测试/ }).click();
  await page.getByRole('textbox', { name: '消息内容' }).waitFor();
  return { page, state, context };
}

try {
  for (const width of [390, 1280]) {
    const { page, state, context } = await fixture(width);
    const input = page.getByRole('textbox', { name: '消息内容' });
    const send = page.getByRole('button', { name: '发送', exact: true });
    assert.equal(state.sends.length, 0, 'legacy queue must not be sent');
    await input.fill('发送失败后保留这段内容');
    await send.click();
    await page.locator('.composer-notice-error').waitFor();
    assert.equal(await input.inputValue(), '发送失败后保留这段内容');
    await page.evaluate(() => {
      window.dispatchEvent(new Event('online'));
      document.dispatchEvent(new Event('visibilitychange'));
    });
    await page.waitForTimeout(5200); // Includes normal polling and SSE reconnection.
    assert.equal(state.sends.length, 1, 'refresh/connectivity events must never resend');
    assert.ok(await page.locator('.composer-notice-error').isVisible());
    assert.equal(
      await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
      false,
    );
    if (screenshots) {
      await mkdir(screenshots, { recursive: true });
      await page.screenshot({ path: `${screenshots}/manual-send-${width}.png` });
    }
    state.mode = 'success';
    await send.click();
    await page.locator('.message-text').filter({ hasText: '发送失败后保留这段内容' }).waitFor();
    assert.equal(await input.inputValue(), '');
    assert.equal(state.sends.length, 2);
    assert.equal(state.sends[0].clientId, state.sends[1].clientId);
    assert.equal(await page.locator('.composer-notice').count(), 0);
    // A write is successful even when both following reads fail.
    state.mode = 'read-failure';
    await input.fill('已经发送成功');
    await send.click();
    await page.getByText('消息已发送，列表暂未更新。', { exact: true }).waitFor();
    assert.equal(await input.inputValue(), '');
    await page.locator('.message-text').filter({ hasText: '已经发送成功' }).waitFor();
    assert.equal(await page.locator('.composer-notice-error').count(), 0);
    const sends = state.sends.length;
    await page.getByRole('button', { name: '刷新', exact: true }).click();
    await page.waitForTimeout(200);
    assert.equal(state.sends.length, sends);
    assert.deepEqual(state.errors, []);
    await context.close();
    console.log(`PASS manual failure/success and responsive layout at ${width}px`);
  }

  {
    const { page, state, context } = await fixture(1280);
    state.mode = 'hold';
    await page.getByRole('textbox', { name: '消息内容' }).fill('发送期间切换会话');
    await page.getByRole('button', { name: '发送', exact: true }).click();
    await page.getByRole('button', { name: /^另一会话/ }).click();
    while (!state.releaseB || !state.releaseSend) await page.waitForTimeout(10);
    const releaseB = state.releaseB;
    state.mode = 'success';
    state.releaseSend();
    await page.waitForTimeout(150);
    releaseB();
    await page.getByText('另一会话正常加载', { exact: true }).waitFor({ timeout: 1500 });
    assert.equal(state.sends.length, 1);
    assert.deepEqual(state.errors, []);
    await context.close();
    console.log('PASS switching conversations during send preserves the new history request');
  }

  {
    const { page, state, context } = await fixture(390);
    const send = page.getByRole('button', { name: '发送', exact: true });
    await page
      .getByLabel('选择附件文件')
      .setInputFiles({
        name: 'notes.txt',
        mimeType: 'text/plain',
        buffer: Buffer.from('test file'),
      });
    await send.click();
    await page.locator('.composer-notice-error').waitFor();
    assert.equal(await page.locator('.attachment-draft').count(), 1);
    state.mode = 'success';
    await send.click();
    await page.getByText('[附件] notes.txt', { exact: true }).waitFor();
    assert.equal(state.sends[0].clientId, state.sends[1].clientId);
    assert.equal(await page.locator('.attachment-draft').count(), 0);
    await page
      .getByLabel('选择附件文件')
      .setInputFiles({
        name: 'notes.txt',
        mimeType: 'text/plain',
        buffer: Buffer.from('cancel this'),
      });
    state.mode = 'cancel';
    await send.click();
    await page.getByRole('button', { name: '取消上传', exact: true }).click();
    await page.getByText('已取消上传，内容已保留。', { exact: true }).waitFor();
    assert.equal(await page.locator('.attachment-draft').count(), 1);
    assert.equal(await page.locator('.composer-notice-error').count(), 0);
    state.releaseSend?.();
    assert.deepEqual(state.errors, []);
    await context.close();
    console.log('PASS attachment failure/manual retry/cancel preserve attachments');
  }
} finally {
  await browser.close();
}
