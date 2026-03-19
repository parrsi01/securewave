#!/usr/bin/env node

'use strict';

const { chromium } = require('playwright');

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function baseUrlFor(pathname) {
  return new URL(pathname, process.env.BASE_URL).toString();
}

async function waitForSelector(page, selector, description) {
  try {
    await page.locator(selector).first().waitFor({ state: 'visible', timeout: 10000 });
  } catch (error) {
    fail(`Timed out waiting for ${description || selector}: ${error.message}`);
  }
}

async function waitForAssistant(page) {
  await waitForSelector(page, '.sw-chat-fab', 'assistant FAB');
  await page.locator('.sw-chat-panel').first().waitFor({ state: 'attached', timeout: 10000 });
}

async function assistantSnapshot(page) {
  return await page.evaluate(() => {
    const panel = document.querySelector('.sw-chat-panel');
    const input = document.querySelector('.sw-chat-input');
    const messages = Array.from(document.querySelectorAll('.sw-chat-bubble')).map((node) => node.textContent || '');
    return {
      isOpen: !!panel && panel.classList.contains('open'),
      draft: input ? input.value : '',
      messageCount: messages.length,
      messages,
    };
  });
}

async function gotoPage(page, pathname, readySelector, description) {
  await page.goto(baseUrlFor(pathname), { waitUntil: 'domcontentloaded' });
  await waitForSelector(page, readySelector, description || pathname);
  await waitForAssistant(page);
}

async function authStatus(page) {
  return await page.evaluate(async () => {
    const response = await fetch('/api/auth/me', { credentials: 'include' });
    let payload = {};
    try {
      payload = await response.json();
    } catch (_error) {}
    return {
      ok: response.ok,
      status: response.status,
      email: payload && payload.email ? payload.email : null,
    };
  });
}

async function assertAuthenticated(page, email, context) {
  const status = await authStatus(page);
  assert(status.ok, `${context}: expected authenticated session, got status ${status.status}`);
  assert(status.email === email, `${context}: expected authenticated email ${email}, got ${status.email}`);
}

async function assertUnauthenticated(page, context) {
  const status = await authStatus(page);
  assert(!status.ok, `${context}: expected unauthenticated session, got status ${status.status}`);
  assert([401, 403].includes(status.status), `${context}: expected 401/403, got ${status.status}`);
}

async function clickVisible(page, selector, description) {
  const locator = page.locator(selector);
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible()) {
      await candidate.click();
      return;
    }
  }
  fail(`No visible element matched ${description || selector}`);
}

async function submitVisible(page, selector, description) {
  const locator = page.locator(selector);
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible()) {
      await candidate.press('Enter');
      return;
    }
  }
  fail(`No visible field matched ${description || selector}`);
}

async function waitForTextChange(page, selector, initialPattern, description) {
  try {
    await page.waitForFunction(
      ({ sel, pattern }) => {
        const node = document.querySelector(sel);
        if (!node) return false;
        const text = (node.textContent || '').trim();
        return text.length > 0 && !new RegExp(pattern, 'i').test(text);
      },
      { sel: selector, pattern: initialPattern },
      { timeout: 10000 },
    );
  } catch (error) {
    fail(`Timed out waiting for ${description || selector} to resolve: ${error.message}`);
  }
}

async function logout(page) {
  await clickVisible(page, '[data-logout]', 'logout button');
  await page.waitForURL('**/login', { timeout: 10000 });
}

async function main() {
  const baseUrl = process.env.BASE_URL;
  const email = process.env.TEST_EMAIL;
  const password = process.env.TEST_PASSWORD;
  const chromiumBin = process.env.CHROMIUM_BIN;

  assert(baseUrl, 'BASE_URL is required');
  assert(email, 'TEST_EMAIL is required');
  assert(password, 'TEST_PASSWORD is required');
  assert(chromiumBin, 'CHROMIUM_BIN is required');

  const browser = await chromium.launch({
    headless: true,
    executablePath: chromiumBin,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });

  const context = await browser.newContext({
    baseURL: baseUrl,
    viewport: { width: 1440, height: 1080 },
  });
  const page = await context.newPage();

  const summary = {
    pagesCovered: [],
    assistant: {},
    auth: {},
    sessionPages: [],
    payment: {},
    gaps: [],
  };

  try {
    await gotoPage(page, '/', 'main', 'landing page');
    summary.pagesCovered.push('/');

    let assistant = await assistantSnapshot(page);
    assert(assistant.messageCount >= 1, 'Assistant should preload at least one message');

    await page.locator('.sw-chat-fab').click();
    await page.waitForFunction(() => document.querySelector('.sw-chat-panel')?.classList.contains('open') === true, null, { timeout: 5000 });

    assistant = await assistantSnapshot(page);
    summary.assistant.initialMessageCount = assistant.messageCount;
    assert(assistant.isOpen, 'Assistant should open from the landing page');

    await clickVisible(page, '.sw-chat-chip', 'assistant quick reply');
    await page.waitForFunction(
      (count) => document.querySelectorAll('.sw-chat-bubble').length > count,
      assistant.messageCount,
      { timeout: 5000 },
    );

    await page.locator('.sw-chat-input').fill('Need help comparing plans later');
    await page.waitForFunction(
      () => document.querySelector('.sw-chat-input')?.value === 'Need help comparing plans later',
      null,
      { timeout: 3000 },
    );

    const assistantAfterReply = await assistantSnapshot(page);
    summary.assistant.messageCountAfterReply = assistantAfterReply.messageCount;
    summary.assistant.draftAfterReply = assistantAfterReply.draft;

    await gotoPage(page, '/services', 'main', 'services page');
    summary.pagesCovered.push('/services');

    const servicesAssistant = await assistantSnapshot(page);
    assert(servicesAssistant.isOpen, 'Assistant open state should persist from landing page to services page');
    assert(servicesAssistant.draft === 'Need help comparing plans later', 'Assistant draft should persist across navigation');
    assert(
      servicesAssistant.messageCount >= assistantAfterReply.messageCount,
      'Assistant history should persist across navigation',
    );

    await page.locator('.sw-chat-close').click();
    await page.waitForFunction(() => document.querySelector('.sw-chat-panel')?.classList.contains('open') === false, null, { timeout: 5000 });

    await gotoPage(page, '/subscription', 'main', 'subscription page');
    summary.pagesCovered.push('/subscription');

    const subscriptionAssistantClosed = await assistantSnapshot(page);
    assert(!subscriptionAssistantClosed.isOpen, 'Assistant minimize state should persist across navigation');

    await clickVisible(page, '[data-open-assistant]', 'assistant trigger button');
    await page.waitForFunction(() => document.querySelector('.sw-chat-panel')?.classList.contains('open') === true, null, { timeout: 5000 });

    const subscriptionAssistantOpen = await assistantSnapshot(page);
    assert(subscriptionAssistantOpen.draft === 'Need help comparing plans later', 'Assistant draft should persist after reopening');
    assert(
      subscriptionAssistantOpen.messageCount >= assistantAfterReply.messageCount,
      'Assistant history should still be available after reopening',
    );
    summary.assistant.openStatePersisted = true;
    summary.assistant.minimizeStatePersisted = true;
    summary.assistant.historyPersisted = true;

    await gotoPage(page, '/login', 'form[data-auth="login"]', 'login form');
    summary.pagesCovered.push('/login');

    await page.locator('form[data-auth="login"] #email').fill('missing@example.com');
    await page.locator('form[data-auth="login"] #password').fill('WrongPass123!');
    await clickVisible(page, 'form[data-auth="login"] button[type="submit"]', 'login submit button');
    await page.locator('form[data-auth="login"] [data-form-message].visible').waitFor({ state: 'visible', timeout: 10000 });
    const invalidLoginMessage = ((await page.locator('form[data-auth="login"] [data-form-message]').textContent()) || '').trim();
    assert(invalidLoginMessage.length > 0, 'Invalid login should render an error message');
    assert(page.url().endsWith('/login'), 'Invalid login should remain on /login');
    summary.auth.invalidLoginMessage = invalidLoginMessage;

    await gotoPage(page, '/register', 'form[data-auth="register"]', 'register form');
    summary.pagesCovered.push('/register');

    await page.locator('form[data-auth="register"] #email').fill(email);
    await page.locator('form[data-auth="register"] #password').fill(password);
    await page.locator('form[data-auth="register"] #passwordConfirm').fill(password);
    await page.locator('form[data-auth="register"] #terms').check();
    await Promise.all([
      page.waitForURL('**/dashboard', { timeout: 10000 }),
      clickVisible(page, 'form[data-auth="register"] button[type="submit"]', 'register submit button'),
    ]);
    await waitForSelector(page, '[data-user-email]', 'dashboard user email');
    await page.waitForFunction(
      (expectedEmail) => document.querySelector('[data-user-email]')?.textContent?.includes(expectedEmail) === true,
      email,
      { timeout: 10000 },
    );

    summary.pagesCovered.push('/dashboard');
    await assertAuthenticated(page, email, 'dashboard after registration');
    summary.auth.registrationRedirectedToDashboard = true;

    await gotoPage(page, '/settings', 'form[data-profile-form]', 'settings page');
    summary.pagesCovered.push('/settings');
    await page.waitForFunction(
      (expectedEmail) => document.querySelector('[data-user-email]')?.value === expectedEmail,
      email,
      { timeout: 10000 },
    );
    await assertAuthenticated(page, email, 'settings page session');
    summary.sessionPages.push('/settings');

    await gotoPage(page, '/diagnostics', '[data-run-diagnostics]', 'diagnostics page');
    summary.pagesCovered.push('/diagnostics');
    await waitForTextChange(page, '[data-diag-api]', 'checking', 'diagnostics API status');
    await waitForTextChange(page, '[data-diag-db]', 'checking', 'diagnostics DB status');
    await assertAuthenticated(page, email, 'diagnostics page session');
    summary.sessionPages.push('/diagnostics');

    await gotoPage(page, '/billing', '[data-checkout-form]', 'billing page');
    summary.pagesCovered.push('/billing');
    await page.waitForFunction(
      () => {
        const select = document.querySelector('[data-plan-select]');
        return !!select && Array.from(select.options).some((option) => option.value);
      },
      null,
      { timeout: 10000 },
    );
    await assertAuthenticated(page, email, 'billing page session');
    summary.sessionPages.push('/billing');

    await logout(page);
    await assertUnauthenticated(page, 'after logout');
    summary.auth.logoutRedirectedToLogin = true;

    await gotoPage(page, '/login', 'form[data-auth="login"]', 'login form for valid credentials');
    await page.locator('form[data-auth="login"] #email').fill(email);
    await page.locator('form[data-auth="login"] #password').fill(password);
    await Promise.all([
      page.waitForURL('**/dashboard', { timeout: 10000 }),
      clickVisible(page, 'form[data-auth="login"] button[type="submit"]', 'valid login submit button'),
    ]);
    await assertAuthenticated(page, email, 'dashboard after valid login');
    summary.auth.validLoginRedirectedToDashboard = true;

    await gotoPage(page, '/billing', '[data-checkout-form]', 'billing page after valid login');
    await assertAuthenticated(page, email, 'billing page after valid login');

    const successCheckoutUrl = baseUrlFor('/billing?mock_checkout=success&session_id=sw_test_checkout');
    const successRoute = async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          checkout_url: successCheckoutUrl,
          session_id: 'sw_test_checkout',
        }),
      });
    };
    await page.route('**/api/payments/stripe/create-checkout-session', successRoute);

    await page.selectOption('[data-plan-select]', { index: 0 });
    await page.selectOption('[data-cycle-select]', 'monthly');
    await Promise.all([
      page.waitForURL('**/billing?mock_checkout=success&session_id=sw_test_checkout', { timeout: 10000 }),
      clickVisible(page, '[data-start-checkout]', 'start checkout button'),
    ]);
    await page.unroute('**/api/payments/stripe/create-checkout-session', successRoute);
    await waitForSelector(page, '[data-checkout-form]', 'billing page after mock checkout success');
    await assertAuthenticated(page, email, 'billing page after checkout redirect');
    summary.payment.successRedirectUrl = page.url();

    const successAlertVisible = await page.locator('[data-checkout-alert]').isVisible().catch(() => false);
    if (!successAlertVisible) {
      summary.gaps.push('Billing success flow redirects correctly but does not render an explicit success confirmation on return.');
    }

    const failureRoute = async (route) => {
      await route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: JSON.stringify({
          error: {
            message: 'Stripe checkout unavailable in test mode.',
          },
        }),
      });
    };
    await page.route('**/api/payments/stripe/create-checkout-session', failureRoute);
    await page.selectOption('[data-plan-select]', { index: 0 });
    await page.selectOption('[data-cycle-select]', 'monthly');
    await clickVisible(page, '[data-start-checkout]', 'start checkout button for failure case');
    await page.locator('[data-checkout-alert]').waitFor({ state: 'visible', timeout: 10000 });
    const failureMessage = ((await page.locator('[data-checkout-alert]').textContent()) || '').trim();
    assert(
      failureMessage.includes('Stripe checkout unavailable in test mode.'),
      `Checkout failure should render the backend error, got: ${failureMessage}`,
    );
    await page.unroute('**/api/payments/stripe/create-checkout-session', failureRoute);
    summary.payment.failureAlertMessage = failureMessage;

    await logout(page);
    await assertUnauthenticated(page, 'after final logout');
    await page.goto(baseUrlFor('/dashboard'), { waitUntil: 'domcontentloaded' });
    await page.waitForURL('**/login', { timeout: 10000 });
    await assertUnauthenticated(page, 'dashboard redirect after logout');
    summary.auth.dashboardProtectedAfterLogout = true;

    process.stdout.write(`${JSON.stringify(summary)}\n`);
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
