// All APIs are mocked in a separate browser context; personal data is never accessed.
import assert from 'node:assert/strict';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const origin = process.env.SYNCBOX_WEB_URL || 'http://127.0.0.1:5173';
const cursor = (m) => `${m.createdAt}|${m.id}`;
try {
  for (const width of [1280, 390]) {
    const context = await browser.newContext({
      viewport: { width, height: 840 },
      isMobile: width < 768,
      hasTouch: width < 768,
    });
    await context.addInitScript(() =>
      sessionStorage.setItem(
        'syncbox-session',
        JSON.stringify({
          accessToken: 'fixture',
          user: { id: 'owner', username: 'fixture', name: 'fixture', deviceId: 'web' },
        }),
      ),
    );
    const page = await context.newPage();
    const errors = [],
      calls = [];
    let failOlder = false;
    const records = Array.from({ length: 96 }, (_, n) => ({
      id: `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`,
      createdAt: new Date(Date.UTC(2026, 10, 9, 0, n)).toISOString(),
      content: `历史消息 ${n}\n${'用于测试可变高度的内容。'.repeat((n % 5) + 1)}`,
      annotation: n % 7 === 0 ? '带批注的消息' : '',
      conversationId: 'first',
      isRead: true,
      isStarred: false,
      senderDevice: {
        id: n % 2 ? 'web' : 'phone',
        name: n % 2 ? 'Web' : 'iPhone',
        platform: 'web',
      },
    }));
    page.on('pageerror', (error) => errors.push(error.message));
    await page.route('**/api/v1/**', async (route) => {
      const url = new URL(route.request().url()),
        path = url.pathname.replace('/api/v1', '');
      const json = (body, status = 200) => route.fulfill({ status, json: body });
      if (path === '/auth/me') return json({ username: 'fixture', deviceId: 'web' });
      if (path === '/devices') return json({ id: 'web', name: 'Web', platform: 'web' });
      if (path === '/events')
        return route.fulfill({ contentType: 'text/event-stream', body: ': fixture\n\n' });
      if (path.endsWith('/read')) return route.fulfill({ status: 204 });
      if (path === '/conversations')
        return json({
          items: [
            { id: 'first', title: '历史测试', preview: '消息', isPinned: false },
            { id: 'second', title: '其他会话', preview: '内容', isPinned: false },
          ],
          total: 2,
          page: 1,
          totalPages: 1,
        });
      if (path.endsWith('/messages')) {
        if (route.request().method() === 'POST') {
          const sent = {
            ...records.at(-1),
            id: '00000000-0000-4000-8000-000000000098',
            createdAt: '2026-11-09T03:00:00.000Z',
            content: route.request().postDataJSON().content,
          };
          records.push(sent);
          return json(sent, 201);
        }
        const before = url.searchParams.get('before'),
          since = url.searchParams.get('since'),
          q = url.searchParams.get('q') || '';
        calls.push({ path, before, since, q });
        if (before && !since) {
          await new Promise((resolve) => setTimeout(resolve, 500));
          if (failOlder) return json({ message: 'offline' }, 503);
        }
        const all = path.includes('/second/') ? [] : records.filter((m) => m.content.includes(q));
        const items = all
          .filter((m) => (!before || cursor(m) < before) && (!since || cursor(m) >= since))
          .reverse();
        const size = Number(url.searchParams.get('pageSize') || 30);
        return json({
          items: items.slice(0, size),
          total: all.length,
          page: 1,
          totalPages: Math.ceil(all.length / size),
          hasMore: items.length > size,
          nextCursor: items.length > size ? cursor(items[size - 1]) : null,
        });
      }
      throw new Error(`Unexpected fixture API ${path}`);
    });
    await page.goto(origin);
    await page.getByRole('button', { name: /^历史测试/ }).click();
    await page.locator(`[data-message-id="${records.at(-1).id}"]`).waitFor();
    assert.equal(await page.getByRole('button', { name: '更早消息', exact: true }).count(), 0);
    const scroller = page.locator('.virtual-message-feed');
    await scroller.evaluate((el) => {
      el.scrollTop = 0;
    });
    await page.waitForFunction(() => {
      const root = document.querySelector('.virtual-message-feed').getBoundingClientRect();
      return [...document.querySelectorAll('[data-message-id]')].some((r) => {
        const box = r.getBoundingClientRect();
        return box.bottom > root.top + 36 && box.top < root.bottom;
      });
    });
    const anchor = await page.locator('[data-message-id]').evaluateAll((rows) => {
      const root = document.querySelector('.virtual-message-feed').getBoundingClientRect();
      const row = rows.find(
        (r) =>
          r.getBoundingClientRect().bottom > root.top + 36 &&
          r.getBoundingClientRect().top < root.bottom,
      );
      return {
        id: row.dataset.messageId,
        top: row.querySelector('.message-card').getBoundingClientRect().top,
      };
    });
    await page.waitForFunction(() =>
      document.querySelector('.history-loader')?.textContent?.includes('正在加载'),
    );
    await page.waitForFunction(() =>
      document.querySelector('.history-loader')?.textContent?.includes('向上滚动'),
    );
    await page.waitForTimeout(100);
    const anchorTop = await page
      .locator(`[data-message-id="${anchor.id}"] .message-card`)
      .evaluate((el) => el.getBoundingClientRect().top);
    assert.ok(
      Math.abs(anchorTop - anchor.top) < 5,
      `prepend moved anchor ${anchorTop - anchor.top}px at ${width}`,
    );
    assert.equal(calls.filter((c) => c.before && !c.since).length, 1);
    const refreshVisible = async () => {
      const count = calls.length;
      await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
      await page.waitForFunction(() => !document.querySelector('.chat-connection-state'));
      await page.waitForTimeout(250);
      assert.ok(calls.length > count);
    };
    records.push({
      ...records.at(-1),
      id: '00000000-0000-4000-8000-000000000096',
      createdAt: '2026-11-09T02:00:00.000Z',
      content: '实时消息',
    });
    await refreshVisible();
    const afterLive = await page
      .locator(`[data-message-id="${anchor.id}"] .message-card`)
      .evaluate((el) => el.getBoundingClientRect().top);
    assert.ok(
      Math.abs(afterLive - anchorTop) < 5,
      `live arrival moved reading position at ${width}`,
    );
    const saved = await scroller.evaluate((el) => el.scrollTop);
    if (width < 768) await page.getByRole('button', { name: '返回会话列表', exact: true }).click();
    await page.getByRole('button', { name: /^其他会话/ }).click();
    if (width < 768) await page.getByRole('button', { name: '返回会话列表', exact: true }).click();
    await page.getByRole('button', { name: /^历史测试/ }).click();
    await page.waitForTimeout(350);
    const restored = await scroller.evaluate((el) => el.scrollTop);
    assert.ok(Math.abs(restored - saved) < 6, `restore ${saved} -> ${restored} at ${width}`);
    failOlder = true;
    await scroller.evaluate((el) => {
      el.scrollTop = 0;
    });
    await page.getByRole('button', { name: '加载失败，点击重试' }).waitFor();
    assert.ok((await page.locator('[data-message-id]').count()) > 0);
    failOlder = false;
    await page.getByRole('button', { name: '加载失败，点击重试' }).click();
    await page.waitForTimeout(700);
    await scroller.evaluate((el) => {
      el.scrollTop = 0;
    });
    await page.waitForTimeout(700);
    assert.equal(await page.getByText('已到最早消息', { exact: true }).count(), 1);
    await page.getByRole('button', { name: '回到底部', exact: true }).click();
    await page.locator(`[data-message-id="${records.at(-1).id}"]`).waitFor();
    records.push({
      ...records.at(-1),
      id: '00000000-0000-4000-8000-000000000097',
      createdAt: '2026-11-09T02:01:00.000Z',
      content: '底部跟随',
    });
    await refreshVisible();
    await page.waitForTimeout(150);
    const bottomGap = await scroller.evaluate(
      (el) => el.scrollHeight - el.scrollTop - el.clientHeight,
    );
    assert.ok(bottomGap < 5, `new arrival did not follow at bottom: ${bottomGap} at ${width}`);
    await scroller.evaluate((el) => {
      el.scrollTop = el.scrollHeight / 2;
    });
    await page.waitForTimeout(100);
    await page.getByRole('button', { name: '展开会话搜索' }).click();
    await page.getByRole('textbox', { name: '搜索当前会话' }).fill('历史消息 1');
    await page.waitForTimeout(650);
    assert.ok((await page.locator('mark').count()) > 0);
    await page.getByRole('textbox', { name: '消息内容', exact: true }).fill('搜索后发送');
    await page.getByRole('button', { name: '发送', exact: true }).click();
    await page.waitForTimeout(400);
    assert.equal(await page.getByRole('textbox', { name: '搜索当前会话' }).inputValue(), '');
    const afterSendGap = await scroller.evaluate(
      (el) => el.scrollHeight - el.scrollTop - el.clientHeight,
    );
    assert.ok(
      afterSendGap < 5,
      `send from search did not return to latest: ${afterSendGap} at ${width}`,
    );
    assert.deepEqual(errors, []);
    console.log(`History scroll/anchor/restore/retry/search: ${width}px passed`);
    await context.close();
  }
} finally {
  await browser.close();
}
