// Isolated UI regression: every API call is mocked; no personal data is accessed.
// Run with a local Vite server, Chrome and PLAYWRIGHT_MODULE pointing to playwright-core.
import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const origin = process.env.SYNCBOX_WEB_URL || 'http://127.0.0.1:5173';
const screenshots = process.env.SYNCBOX_SCREENSHOTS || '/private/tmp/syncbox-telegram-ui';
// Use SYNCBOX_TEST_MODE=highlighter for the focused search regression only.
const mode = process.env.SYNCBOX_TEST_MODE || 'all';
const conversationId = '11111111-1111-4111-8111-111111111111';
const device = { id: 'fixture-web', name: 'Mac 浏览器', platform: 'web' };
const user = { id: 'fixture-owner', username: 'fixture', name: '测试账号', deviceId: device.id };
const other = { id: 'fixture-phone', name: 'iPhone', platform: 'ios' };
const text = '在电脑上打开 https://example.com/docs?q=sync 。';
const unsafe = '<img src=x onerror="window.unsafeMarkup=true"> javascript:alert(1)';
const pageResult = (items) => ({ items, total: items.length, page: 1, totalPages: 1 });
function message(id, content, createdAt, senderDevice = other, extra = {}) {
  return {
    id,
    content,
    createdAt,
    senderDevice,
    conversationId,
    isRead: true,
    isStarred: false,
    ...extra,
  };
}

async function fixture(width, compact = false) {
  const mobile = width < 768;
  const context = await browser.newContext({
    viewport: { width, height: 860 },
    hasTouch: mobile,
    isMobile: mobile,
  });
  await context.addInitScript(
    ({ user }) => {
      sessionStorage.setItem(
        'syncbox-session',
        JSON.stringify({ accessToken: 'fixture-token', user }),
      );
      // Exercise the same fallback used on non-secure LAN HTTP, without permission dialogs.
      Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
      window.copiedText = [];
      document.execCommand = (command) => {
        if (command !== 'copy') return false;
        const el = document.activeElement;
        window.copyDebug = {
          active: el?.outerHTML,
          fields: [...document.querySelectorAll('textarea')].map((field) => ({
            value: field.value,
            start: field.selectionStart,
            end: field.selectionEnd,
          })),
        };
        window.copiedText.push(
          el?.value?.slice(el.selectionStart, el.selectionEnd) ?? String(getSelection()),
        );
        return true;
      };
    },
    { user },
  );
  const page = await context.newPage();
  page.setDefaultTimeout(6000);
  const state = {
    sends: [],
    deletes: [],
    patches: [],
    errors: [],
    failSend: false,
    holdCleanup: false,
    finishCleanup: null,
    messages: [
      message('previous-day', '昨天整理好的资料。', '2026-11-08T11:00:00+08:00'),
      message('link', text, '2026-11-09T10:00:00+08:00'),
      message('own', '收到，电脑上可以继续编辑。', '2026-11-09T10:01:00+08:00', device),
      message('long', '这段文案保留完整内容。'.repeat(15), '2026-11-09T10:03:00+08:00', other, {
        annotation: '用于移动端和电脑端的内容同步。',
      }),
      message('file', '[附件] 产品说明.pdf', '2026-11-09T10:12:00+08:00', device, {
        attachments: [
          {
            id: 'fixture-file',
            name: '产品说明.pdf',
            size: 204800,
            mimeType: 'application/pdf',
            hasPreview: false,
            width: null,
            height: null,
          },
        ],
      }),
      message('unsafe', unsafe, '2026-11-09T10:13:00+08:00'),
    ],
  };
  if (compact)
    state.messages = [
      message('previous-day', '昨天的消息', '2026-11-08T11:00:00+08:00'),
      message('link', '今天的第一条', '2026-11-09T10:00:00+08:00'),
      message('own', '同一天的一分钟后', '2026-11-09T10:01:00+08:00', device),
      message('unsafe', '同一天的十二分钟后', '2026-11-09T10:12:00+08:00'),
    ];
  if (compact === 'image')
    state.messages = [
      message('unsafe', '[图片]', '2026-11-09T10:00:00+08:00', other, {
        image: { mimeType: 'image/png', width: 160, height: 100, size: 67 },
      }),
    ];
  if (compact === 'multi-image')
    state.messages = [
      message(
        'gallery',
        '[附件] image-1.png、image-2.png、image-3.png',
        '2026-11-09T10:00:00+08:00',
        other,
        {
          attachments: [1, 2, 3].map((index) => ({
            id: `gallery-${index}`,
            name: `image-${index}.png`,
            size: index * 1024,
            mimeType: 'image/png',
            hasPreview: true,
            width: 640,
            height: index === 2 ? 900 : 480,
            deletedAt: null,
          })),
        },
      ),
    ];
  page.on('pageerror', (error) => state.errors.push(error.message));
  await page.route('**/api/v1/**', async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    const path = url.pathname.replace('/api/v1', '');
    const json = (body, status = 200) => route.fulfill({ status, json: body });
    if (path === '/auth/me') return json(user);
    if (path === '/devices/heartbeat') return route.fulfill({ status: 204 });
    if (path === '/devices') return json(req.method() === 'POST' ? device : [device, other]);
    const settings = {
      cleanup: { enabled: false, idleDays: 30, lastRunAt: null, lastDeletedCount: 0 },
      twoFactorEnabled: false,
      recoveryCodesRemaining: 0,
      storage: { fileCount: 0, bytes: 0 },
    };
    if (path === '/settings') return json(settings);
    if (path === '/settings/cleanup') {
      if (state.holdCleanup)
        await new Promise((resolve) => {
          state.finishCleanup = resolve;
        });
      return json(settings);
    }
    if (path === '/settings/two-factor/setup')
      return json({
        secret: 'JBSWY3DPEHPK3PXP',
        otpauthUri: 'otpauth://totp/Fixture?secret=JBSWY3DPEHPK3PXP',
        expiresIn: 600,
      });
    if (path === '/settings/two-factor/enable')
      return json({ recoveryCodes: ['FIXTURE-RECOVERY-1', 'FIXTURE-RECOVERY-2'] });
    if (path === '/events')
      return route.fulfill({
        status: 200,
        contentType: 'text/event-stream',
        body: ': fixture\n\n',
      });
    if (path === '/messages/unsafe/image')
      return route.fulfill({
        status: 200,
        contentType: 'image/png',
        body: Buffer.from(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jV9sAAAAASUVORK5CYII=',
          'base64',
        ),
      });
    if (path.startsWith('/messages/gallery/attachments/') && path.endsWith('/preview'))
      return route.fulfill({
        status: 200,
        contentType: 'image/png',
        body: Buffer.from(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jV9sAAAAASUVORK5CYII=',
          'base64',
        ),
      });
    if (path.endsWith('/read')) return route.fulfill({ status: 204 });
    if (path === '/conversations')
      return json(
        pageResult([
          {
            id: conversationId,
            title: '随手传',
            isPinned: true,
            unreadCount: 9,
            preview: '手机和电脑，共享这一刻',
            updatedAt: '2026-11-09T10:13:00+08:00',
          },
          {
            id: 'second',
            title: '工作资料',
            preview: '产品说明.pdf',
            updatedAt: '2026-11-08T10:00:00+08:00',
          },
        ]),
      );
    if (path === '/messages/starred') {
      const query = (url.searchParams.get('q') ?? '').toLowerCase();
      return json(
        pageResult(
          state.messages
            .filter(
              (m) =>
                !query ||
                [m.content, m.annotation, ...(m.attachments ?? []).map((file) => file.name)].some(
                  (value) => value?.toLowerCase().includes(query),
                ),
            )
            .map((m) => ({ ...m, isStarred: true, conversationTitle: '随手传' })),
        ),
      );
    }
    if (path === `/conversations/${conversationId}/messages`) {
      if (req.method() === 'POST') {
        const body = req.postDataJSON();
        state.sends.push(body);
        if (state.failSend) return json({ message: '测试服务暂不可用' }, 503);
        const sent = message(
          `sent-${state.sends.length}`,
          body.content,
          new Date().toISOString(),
          device,
        );
        state.messages.push(sent);
        return json(sent, 201);
      }
      const query = (url.searchParams.get('q') ?? '').toLowerCase();
      return json(
        pageResult(
          [...state.messages]
            .filter(
              (m) =>
                !query ||
                [m.content, m.annotation, ...(m.attachments ?? []).map((file) => file.name)].some(
                  (value) => value?.toLowerCase().includes(query),
                ),
            )
            .reverse(),
        ),
      );
    }
    if (path.startsWith('/messages/') && req.method() === 'PATCH') {
      const id = path.split('/').at(-1),
        patch = req.postDataJSON();
      state.patches.push({ id, patch });
      const target = state.messages.find((m) => m.id === id);
      Object.assign(target, patch);
      return json(target);
    }
    if (path.startsWith('/messages/') && req.method() === 'DELETE') {
      state.deletes.push(path);
      return route.fulfill({ status: 204 });
    }
    throw new Error(`Unexpected fixture request: ${req.method()} ${path}`);
  });
  await page.goto(origin);
  await page.getByRole('button', { name: /^随手传/ }).click();
  await page.getByRole('textbox', { name: '消息内容' }).waitFor();
  await page
    .locator(`[data-message-id="${compact === 'multi-image' ? 'gallery' : 'unsafe'}"]`)
    .waitFor();
  return { context, page, state, mobile };
}

async function showMessage(page, id) {
  const row = page.locator(`[data-message-id="${id}"]`);
  if (!(await row.count())) {
    await page.locator('.virtual-message-feed').evaluate((el) => {
      el.scrollTop = 0;
    });
    await row.waitFor();
  }
  await row.scrollIntoViewIfNeeded();
  return row;
}

async function openMenu(page, id, touch = false) {
  const row = await showMessage(page, id);
  const target = row.locator('.message-bubble');
  if (touch) {
    const box = await target.boundingBox();
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [{ x: box.x + box.width / 2, y: box.y + 16 }],
    });
    await page.waitForTimeout(850);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await cdp.detach();
  } else await target.click({ button: 'right' });
  await page.getByRole('menuitem', { name: '复制内容', exact: true }).waitFor();
  return row;
}

try {
  await mkdir(screenshots, { recursive: true });
  if (mode === 'all' || mode === 'navigation') {
    for (const width of [360, 390, 768, 1280]) {
      const { context, page, state, mobile } = await fixture(width, true);
      const nav = page.getByRole('navigation', { name: '主导航', exact: true });
      assert.equal(await nav.count(), 0, 'chat detail has no bottom navigation');
      await page.getByRole('button', { name: '更多会话操作', exact: true }).click();
      assert.ok(
        await page.getByRole('menuitem', { name: '取消置顶会话', exact: true }).isVisible(),
      );
      await page.keyboard.press('Escape');
      const draft = page.getByRole('textbox', { name: '消息内容' });
      await draft.fill('保留未发送的草稿');
      if (mobile) {
        await page.getByRole('button', { name: '返回会话列表' }).click();
        assert.ok(await page.getByRole('heading', { name: '消息列表', exact: true }).isVisible());
        const title = await page.locator('.workspace-brand').boundingBox();
        const create = await page
          .getByRole('button', { name: '创建会话', exact: true })
          .boundingBox();
        assert.ok(
          create.x > width / 2 &&
            create.y >= title.y &&
            create.y + create.height <= title.y + title.height,
        );
        await page.screenshot({ path: `${screenshots}/messages-list-${width}.png` });
        await nav.getByRole('button', { name: '设置', exact: true }).click();
        await page.getByRole('region', { name: '设置', exact: true }).waitFor();
        assert.equal(
          await nav.getByRole('button', { name: '设置', exact: true }).getAttribute('aria-current'),
          'page',
        );
      } else {
        await page.getByRole('button', { name: '打开设置', exact: true }).click();
        await page.getByRole('dialog', { name: '设置', exact: true }).waitFor();
      }
      await page.getByLabel('设备名称', { exact: true }).waitFor();
      const region = page.locator('.settings-panel');
      assert.equal(await page.getByLabel('当前设备标识', { exact: true }).isVisible(), false);
      await page.locator('.device-identity-details > summary').click();
      assert.equal(await page.getByLabel('当前设备标识', { exact: true }).inputValue(), device.id);
      await page.locator('.device-identity-details > summary').click();
      await page.screenshot({ path: `${screenshots}/settings-${width}.png` });
      if (mobile) {
        await page.setViewportSize({ width: 1024, height: 860 });
        await page.getByRole('dialog', { name: '设置', exact: true }).waitFor();
        assert.equal(await nav.count(), 0);
        await page.setViewportSize({ width, height: 860 });
        await page.getByRole('region', { name: '设置', exact: true }).waitFor();
        const settingsBox = await region.boundingBox();
        const navBox = await nav.boundingBox();
        assert.ok(
          settingsBox.y + settingsBox.height <= navBox.y + 1,
          'settings scrolls above navigation',
        );
        // Saving must keep the page mounted; a response cannot be lost to tab changes.
        state.holdCleanup = true;
        await page.getByRole('button', { name: '保存清理设置', exact: true }).click();
        await page.waitForFunction(
          () => document.querySelector('.mobile-workspace-nav button').disabled,
        );
        assert.equal(
          await nav.getByRole('button', { name: '消息', exact: true }).isDisabled(),
          true,
        );
        state.finishCleanup();
        await page.getByText('文件清理设置已保存。', { exact: true }).waitFor();
        // Recovery codes must be acknowledged before leaving this page.
        await page.getByRole('switch', { name: '两步认证', exact: true }).click();
        await page.getByLabel('当前密码', { exact: true }).fill('fixture-password');
        await page.getByRole('button', { name: '下一步：绑定验证器', exact: true }).click();
        await page.getByRole('textbox', { name: /^6 位动态码/ }).fill('123456');
        await page.getByRole('button', { name: '验证并开启', exact: true }).click();
        await page.getByText('FIXTURE-RECOVERY-1', { exact: true }).waitFor();
        assert.equal(
          await nav.getByRole('button', { name: '消息', exact: true }).isDisabled(),
          true,
        );
        await page.getByRole('checkbox', { name: '我已安全保存恢复码', exact: true }).check();
        await nav.getByRole('button', { name: '消息', exact: true }).click();
        await page.getByRole('button', { name: /^随手传/ }).click();
      } else {
        await page.getByRole('button', { name: '关闭设置', exact: true }).click();
      }
      assert.equal(await draft.inputValue(), '保留未发送的草稿');
      assert.equal(state.sends.length, 0);
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
      );
      assert.deepEqual(state.errors, []);
      await context.close();
      console.log(`PASS navigation, settings, draft and safety guards at ${width}px`);
    }
  }
  if (mode === 'all' || mode === 'baseline') {
    for (const width of [1280, 913, 390]) {
      const { context, page, state, mobile } = await fixture(width);
      assert.equal(await page.locator('.conversation-unread').count(), 0);
      assert.equal(await page.locator('.chat-search').isVisible(), false);
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
      );
      assert.equal(await page.locator('.conversation-pane').isVisible(), !mobile);

      const own = await showMessage(page, 'own');
      const ownBox = await own.locator('.message-bubble').boundingBox();
      const incoming = await showMessage(page, 'link');
      const otherBox = await incoming.locator('.message-bubble').boundingBox();
      assert.ok(ownBox.x > otherBox.x, 'outgoing messages align right');
      const incomingColor = await incoming
        .locator('.message-bubble')
        .evaluate((el) => getComputedStyle(el).backgroundColor);
      const ownColor = await own
        .locator('.message-bubble')
        .evaluate((el) => getComputedStyle(el).backgroundColor);
      assert.equal(incomingColor, 'rgb(255, 255, 255)');
      assert.notEqual(ownColor, incomingColor);
      const channels = ownColor.match(/\d+/g).map(Number);
      assert.ok(channels[2] > channels[0], 'outgoing bubble is blue-tinted');
      assert.ok(await own.locator('time').count(), 'every message has its own time');
      const timeBox = await own.locator('time').boundingBox();
      const textBox = await own.locator('.message-text').boundingBox();
      assert.ok(timeBox.y >= textBox.y, 'message time appears below body start');
      const link = incoming.getByRole('link', { name: 'https://example.com/docs?q=sync' });
      assert.equal(await link.getAttribute('href'), 'https://example.com/docs?q=sync');
      assert.equal(await link.getAttribute('target'), '_blank');
      assert.ok((await link.getAttribute('rel')).includes('noopener'));
      const unsafeRow = await showMessage(page, 'unsafe');
      assert.equal(await unsafeRow.locator('.message-text img, .message-text script').count(), 0);
      assert.equal(await unsafeRow.locator('a[href^="javascript:"]').count(), 0);
      assert.equal(await page.evaluate(() => window.unsafeMarkup), undefined);

      await page.getByRole('button', { name: '展开会话搜索' }).click();
      assert.equal(await page.locator('.chat-search').isVisible(), true);
      assert.equal(
        await page
          .getByRole('textbox', { name: '搜索当前会话' })
          .evaluate((el) => el === document.activeElement),
        true,
      );
      await page.getByRole('button', { name: '收起会话搜索' }).click();
      await page.screenshot({ path: `${screenshots}/telegram-${width}.png` });
      await showMessage(page, 'previous-day');
      await page.screenshot({ path: `${screenshots}/telegram-history-${width}.png` });

      await openMenu(page, 'link', mobile);
      for (const name of ['收藏消息', '添加批注', '删除消息'])
        assert.ok(await page.getByRole('menuitem', { name, exact: true }).isVisible());
      await page.getByRole('menuitem', { name: '复制内容', exact: true }).click();
      await page.waitForFunction(() => window.copiedText.length > 0);
      assert.equal(
        await page.evaluate(() => window.copiedText.at(-1)),
        text,
        `LAN fallback copies the complete text: ${JSON.stringify(await page.evaluate(() => window.copyDebug))}`,
      );
      // Wait for transient copied menu label to return before reopening.
      await page.waitForTimeout(1900);
      await openMenu(page, 'link', mobile);
      await page.getByRole('menuitem', { name: '删除消息', exact: true }).click();
      await page.getByRole('dialog', { name: '删除这条消息？' }).waitFor();
      await page.getByRole('button', { name: '取消', exact: true }).click();
      assert.equal(state.deletes.length, 0);
      await openMenu(page, 'link', mobile);
      await page.getByRole('menuitem', { name: '添加批注', exact: true }).click();
      await page.getByRole('dialog', { name: '添加批注' }).waitFor();
      assert.equal(
        await page
          .getByRole('textbox', { name: '批注', exact: true })
          .evaluate((el) => el === document.activeElement),
        true,
      );
      await page.getByRole('button', { name: '关闭批注' }).click();

      const input = page.getByRole('textbox', { name: '消息内容' });
      await input.fill('第一行');
      await input.press('Shift+Enter');
      await input.press('End');
      await input.type('第二行');
      assert.equal(await input.inputValue(), '第一行\n第二行');
      assert.equal(state.sends.length, 0);
      await input.evaluate((el) => {
        el.dispatchEvent(
          new KeyboardEvent('keydown', {
            key: 'Enter',
            code: 'Enter',
            isComposing: true,
            bubbles: true,
          }),
        );
        el.dispatchEvent(
          new KeyboardEvent('keydown', {
            key: 'Enter',
            code: 'Enter',
            keyCode: 229,
            bubbles: true,
          }),
        );
      });
      await page.waitForTimeout(100);
      assert.equal(state.sends.length, 0, 'IME Enter never sends');
      await input.press('Enter');
      if (mobile) {
        assert.equal(state.sends.length, 0);
        assert.equal(await input.inputValue(), '第一行\n第二行\n');
        await page.getByRole('button', { name: '发送', exact: true }).click();
      }
      await page.waitForFunction(
        () => document.querySelector('textarea[aria-label="消息内容"]').value === '',
      );
      assert.equal(state.sends.length, 1);
      assert.equal(state.sends[0].content, '第一行\n第二行');

      state.failSend = true;
      await input.fill('失败后手动再发');
      await page.getByRole('button', { name: '发送', exact: true }).click();
      await page.locator('.composer-notice-error').waitFor();
      assert.equal(await input.inputValue(), '失败后手动再发');
      await page.evaluate(() => window.dispatchEvent(new Event('online')));
      await page.waitForTimeout(100);
      assert.equal(state.sends.length, 2);
      assert.deepEqual(state.errors, []);
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
      );
      if (mobile) {
        await page.setViewportSize({ width: 390, height: 340 });
        await input.fill('窄屏长草稿，保留发送入口。\n'.repeat(25));
        await page.getByLabel('选择附件文件').setInputFiles(
          Array.from({ length: 5 }, (_, i) => ({
            name: `草稿附件-${i + 1}.txt`,
            mimeType: 'text/plain',
            buffer: Buffer.from('fixture'),
          })),
        );
        await page.waitForTimeout(200);
        const box = await page.getByRole('button', { name: '发送', exact: true }).boundingBox();
        assert.ok(
          box.y >= 0 && box.y + box.height <= 340,
          'send remains visible above small viewport bottom',
        );
        assert.equal(
          await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
          false,
        );
        await page.screenshot({ path: `${screenshots}/telegram-mobile-keyboard.png` });
      }
      await context.close();
      console.log(`PASS Telegram workspace layout and interactions at ${width}px`);
    }
    {
      // A minimal history isolates day grouping from virtualized offscreen rows.
      const { context, page } = await fixture(1280, true);
      await showMessage(page, 'previous-day');
      assert.equal(
        await page.locator('.message-date-separator').count(),
        2,
        'date headers group by day, not by a five-minute gap',
      );
      assert.equal(await page.locator('.message-footer time').count(), 4);
      const dates = await page.locator('.message-date-separator time').allTextContents();
      assert.equal(new Set(dates).size, 2);
      await context.close();
      console.log('PASS daily grouping and per-message timestamps');
    }
    for (const width of [1280, 390]) {
      const { context, page } = await fixture(width, 'image');
      await page.getByRole('button', { name: '查看大图' }).click();
      await page.getByRole('dialog', { name: '图片预览' }).waitFor();
      assert.equal(
        await page
          .locator('.image-lightbox img')
          .evaluate((img) => img.complete && img.naturalWidth > 0),
        true,
      );
      await page.getByRole('button', { name: '关闭图片预览' }).click();
      assert.equal(await page.getByRole('dialog', { name: '图片预览' }).count(), 0);
      await context.close();
      console.log(`PASS image preview open/close at ${width}px`);
    }
    for (const width of [1280, 390]) {
      const { context, page } = await fixture(width, 'multi-image');
      const gallery = await showMessage(page, 'gallery');
      assert.equal(await gallery.locator('.message-image-grid').count(), 1);
      assert.equal(await gallery.locator('.attachment-image-tile').count(), 3);
      assert.equal(await gallery.locator('.attachment-file-row').count(), 0);
      assert.equal(await gallery.locator('.attachment-image-download').count(), 3);
      await gallery
        .locator('.attachment-image-tile')
        .first()
        .getByRole('button', { name: /^查看大图/ })
        .click();
      await page.getByRole('dialog', { name: '图片预览' }).waitFor();
      assert.equal(await page.getByText('1 / 3', { exact: true }).count(), 1);
      await page.getByRole('button', { name: '下一张图片' }).click();
      assert.equal(await page.getByText('2 / 3', { exact: true }).count(), 1);
      await page.keyboard.press('ArrowRight');
      assert.equal(await page.getByText('3 / 3', { exact: true }).count(), 1);
      await page.getByRole('button', { name: '关闭图片预览' }).click();
      await page.screenshot({ path: `${screenshots}/telegram-multi-image-${width}.png` });
      await context.close();
      console.log(`PASS multi-image grid and viewer at ${width}px`);
    }
  }
  if (mode === 'all' || mode === 'highlighter') {
    for (const width of [1280, 390]) {
      const { context, page, state, mobile } = await fixture(width);
      await page.getByRole('button', { name: '展开会话搜索' }).click();
      const search = page.getByRole('textbox', { name: '搜索当前会话' });
      await search.fill('电脑');
      const bodyMark = page.locator('[data-message-id="link"] .message-text mark.search-highlight');
      await bodyMark.waitFor();
      assert.equal(await bodyMark.textContent(), '电脑');

      await search.fill('EXAMPLE');
      const markedLink = page.locator('[data-message-id="link"] .message-text a');
      const linkMark = markedLink.locator('mark.search-highlight');
      await linkMark.waitFor();
      assert.equal(
        await linkMark.textContent(),
        'example',
        'case-insensitive match preserves original casing',
      );
      assert.equal(await markedLink.getAttribute('href'), 'https://example.com/docs?q=sync');
      assert.equal(await markedLink.textContent(), 'https://example.com/docs?q=sync');
      await page.screenshot({ path: `${screenshots}/telegram-highlight-link-${width}.png` });
      await openMenu(page, 'link', mobile);
      await page.getByRole('menuitem', { name: '复制内容', exact: true }).click();
      await page.waitForFunction(() => window.copiedText.length > 0);
      assert.equal(
        await page.evaluate(() => window.copiedText.at(-1)),
        text,
        'highlighting never changes copied text',
      );

      state.messages.find((m) => m.id === 'long').annotation =
        '前面的批注内容。\n'.repeat(8) + '移动端高亮在折叠范围之后。';
      await search.fill('移动端');
      const annotationMark = page.locator(
        '[data-message-id="long"] .message-annotation mark.search-highlight',
      );
      await annotationMark.waitFor();
      assert.equal(await annotationMark.textContent(), '移动端');
      assert.equal(await page.locator('[data-message-id="long"] .annotation-collapsed').count(), 0);
      await page.screenshot({ path: `${screenshots}/telegram-highlight-note-${width}.png` });

      await search.fill('产品说明');
      const fileMark = page.locator(
        '[data-message-id="file"] .attachment-file-info mark.search-highlight',
      );
      await fileMark.waitFor();
      assert.equal(await fileMark.textContent(), '产品说明');
      assert.equal(
        await page.locator('[data-message-id="file"] .attachment-file-info strong').textContent(),
        '产品说明.pdf',
      );

      await page.getByRole('button', { name: '清空会话搜索' }).click();
      await page.waitForFunction(
        () => document.querySelectorAll('.message-feed mark.search-highlight').length === 0,
      );
      assert.equal(await search.inputValue(), '');
      if (mobile) await page.getByRole('button', { name: '返回会话列表' }).click();
      await page.getByRole('textbox', { name: '搜索会话、消息、批注或文件名' }).fill('随手');
      const titleMark = page.locator('.conversation-name mark.search-highlight');
      await titleMark.waitFor();
      assert.equal(await titleMark.textContent(), '随手');
      await page.screenshot({ path: `${screenshots}/telegram-highlight-sidebar-${width}.png` });
      await page.getByRole('button', { name: '查看收藏' }).click();
      const favoriteSearch = page.getByRole('textbox', { name: '搜索收藏' });
      await favoriteSearch.fill('移动端');
      const favoriteNote = page.locator(
        '.favorites-content .message-annotation mark.search-highlight',
      );
      await favoriteNote.waitFor();
      assert.equal(await favoriteNote.textContent(), '移动端');
      await favoriteSearch.fill('产品说明');
      const favoriteFile = page.locator(
        '.favorites-content .attachment-file-info mark.search-highlight',
      );
      await favoriteFile.waitFor();
      assert.equal(await favoriteFile.textContent(), '产品说明');
      await page.getByRole('button', { name: '关闭收藏' }).click();
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
      );
      assert.deepEqual(state.errors, []);
      assert.equal(state.sends.length, 0);
      await context.close();
      console.log(`PASS search highlight body/link/note/file/title and copy at ${width}px`);
    }
  }
} finally {
  await browser.close();
}
