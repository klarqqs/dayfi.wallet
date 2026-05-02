// src/routes/payments.js  —  mounts at /api/payments
//
// GET  /api/payments/virtual-account
// POST /api/payments/virtual-account
// POST /api/payments/flutterwave/init
// POST /api/payments/flutterwave/verify
// POST /api/payments/flutterwave/webhook
// POST /api/payments/flutterwave/withdraw
// GET  /api/payments/flutterwave/banks
// POST /api/payments/flutterwave/resolve-account

import express from 'express';
import { body, validationResult } from 'express-validator';
import { authenticate } from '../middleware/auth.js';
import { PrismaClient } from '@prisma/client';
import { sendAssetFromMasterWallet } from '../services/walletService.js';

const router = express.Router();
const prisma = new PrismaClient();

const FLW_SECRET       = process.env.FLUTTERWAVE_SECRET_KEY || '';
const FLW_WEBHOOK_HASH = process.env.FLUTTERWAVE_WEBHOOK_HASH || process.env.FLUTTERWAVE_WEBHOOK_SECRET_HASH || '';

const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function flwRequest(path, method = 'GET', payload = null, retries = 2) {
  let attempt = 0, lastErr = null;
  while (attempt <= retries) {
    const ctrl = new AbortController();
    const tid  = setTimeout(() => ctrl.abort(), 15000);
    try {
      const res = await fetch(`https://api.flutterwave.com/v3${path}`, {
        method,
        headers: { Authorization: `Bearer ${FLW_SECRET}`, 'Content-Type': 'application/json' },
        ...(payload ? { body: JSON.stringify(payload) } : {}),
        signal: ctrl.signal,
      });
      clearTimeout(tid);
      const data = await res.json();
      if (!res.ok || data?.status !== 'success') {
        const err = new Error(data?.message || `Flutterwave error (${res.status})`);
        err.status = res.status;
        throw err;
      }
      return data.data;
    } catch (err) {
      clearTimeout(tid);
      lastErr = err;
      if (attempt === retries || !RETRYABLE.has(err?.status)) break;
      await sleep(300 * (attempt + 1));
      attempt++;
    }
  }
  throw lastErr || new Error('Flutterwave request failed');
}

function ensureFlw(res) {
  if (!FLW_SECRET) {
    res.status(503).json({ error: 'PAYMENT_PROVIDER_UNAVAILABLE', message: 'Flutterwave not configured.' });
    return false;
  }
  return true;
}

function isSuccess(status) {
  const s = String(status || '').toLowerCase();
  return s === 'successful' || s === 'completed' || s === 'success';
}

// ─── Deposit settlement helper ────────────────────────────────────────────────

async function processDepositSuccess({ userId, txRef, flwRef, amount, currency = 'NGN', providerStatus = 'successful', providerMessage = null }) {
  const amountNum = Number(amount || 0);
  if (!amountNum || amountNum <= 0) return { processed: false, reason: 'invalid_amount' };

  await prisma.flutterwavePayment.upsert({
    where: { txRef },
    create: {
      userId, txRef,
      flwRef: flwRef ? String(flwRef) : null,
      type: 'deposit',
      fiatAmount: amountNum,
      currency: String(currency || 'NGN').toUpperCase(),
      status: 'successful',
      providerStatus: String(providerStatus).toLowerCase(),
      providerMessage: providerMessage || null,
    },
    update: {
      flwRef: flwRef ? String(flwRef) : undefined,
      fiatAmount: amountNum,
      status: 'successful',
      providerStatus: String(providerStatus).toLowerCase(),
      providerMessage: providerMessage || null,
    },
  });

  const existingFiatTx = await prisma.transaction.findFirst({
    where: { userId, type: 'fiatDeposit', flutterwaveRef: txRef },
  });
  let fiatTxId = existingFiatTx?.id || null;
  if (!existingFiatTx) {
    const created = await prisma.transaction.create({
      data: {
        userId, type: 'fiatDeposit', status: 'confirmed',
        amount: amountNum, asset: 'NGNT', network: 'flutterwave',
        flutterwaveRef: txRef,
        fiatAmount: amountNum,
        fiatCurrency: String(currency || 'NGN').toUpperCase(),
        flutterwaveStatus: String(providerStatus).toLowerCase(),
        memo: 'Flutterwave NGN top-up',
      },
    });
    fiatTxId = created.id;
  }

  let settlement = null;
  const autoSettle = String(process.env.AUTO_SETTLE_NGNT_TOPUPS || 'true').toLowerCase() === 'true';
  if (autoSettle) {
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { stellarPublicKey: true } });
    if (user?.stellarPublicKey) {
      const settledAlready = await prisma.transaction.findFirst({
        where: { userId, type: 'receive', network: 'stellar', flutterwaveRef: txRef, asset: 'NGNT' },
      });
      if (!settledAlready) {
        try {
          const memo = `Top-up ${txRef}`.slice(0, 28);
          const sent = await sendAssetFromMasterWallet(user.stellarPublicKey, amountNum, 'NGNT', memo);
          await prisma.transaction.create({
            data: {
              userId, type: 'receive', status: 'confirmed',
              amount: amountNum, asset: 'NGNT', network: 'stellar',
              fromAddress: process.env.MASTER_WALLET_PUBLIC_KEY || null,
              toAddress: user.stellarPublicKey,
              stellarTxHash: sent.hash,
              flutterwaveRef: txRef,
              memo: 'NGNT settlement from top-up',
            },
          });
          settlement = { status: 'settled', hash: sent.hash, amount: amountNum };
        } catch (err) {
          settlement = { status: 'settlement_failed', error: err.message };
        }
      } else {
        settlement = { status: 'already_settled' };
      }
    } else {
      settlement = { status: 'wallet_not_ready' };
    }
  } else {
    settlement = { status: 'disabled' };
  }

  if (fiatTxId) {
    const settlementStatus = settlement?.status === 'settled' || settlement?.status === 'already_settled'
      ? 'settled' : 'pending_settlement';
    await prisma.transaction.update({ where: { id: fiatTxId }, data: { flutterwaveStatus: settlementStatus } });
  }

  return { processed: true, settlement };
}

// ─── GET /api/payments/virtual-account ───────────────────────────────────────

router.get('/virtual-account', authenticate, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { virtualAccountNumber: true, virtualAccountBank: true, virtualAccountName: true },
    });
    if (!user) return res.status(404).json({ error: 'User not found' });
    if (!user.virtualAccountNumber) return res.json({ exists: false });
    return res.json({
      exists: true,
      accountNumber: user.virtualAccountNumber,
      bankName:      user.virtualAccountBank,
      accountName:   user.virtualAccountName,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/payments/virtual-account ──────────────────────────────────────

router.post('/virtual-account', authenticate, [
  body('bvn').isLength({ min: 11, max: 11 }).withMessage('BVN must be 11 digits').matches(/^\d{11}$/).withMessage('BVN must be numeric'),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { bvn } = req.body;
  try {
    const existing = await prisma.user.findUnique({
      where: { id: req.user.id },
      select: { virtualAccountNumber: true, virtualAccountBank: true, virtualAccountName: true, email: true, username: true },
    });
    if (!existing) return res.status(404).json({ error: 'User not found' });

    if (existing.virtualAccountNumber) {
      return res.json({
        accountNumber: existing.virtualAccountNumber,
        bankName:      existing.virtualAccountBank,
        accountName:   existing.virtualAccountName,
      });
    }

    if (!FLW_SECRET) {
      console.warn('⚠️  FLUTTERWAVE_SECRET_KEY not set — returning mock virtual account');
      const mock = { accountNumber: '1234567890', bankName: 'Wema Bank', accountName: existing.username || existing.email };
      await prisma.user.update({ where: { id: req.user.id }, data: { virtualAccountNumber: mock.accountNumber, virtualAccountBank: mock.bankName, virtualAccountName: mock.accountName } });
      return res.json(mock);
    }

    const accountName = existing.username || existing.email;
    const txRef = `dayfi-va-${req.user.id}-${Date.now()}`;

    const flwData = await flwRequest('/virtual-account-numbers', 'POST', {
      email: existing.email,
      is_permanent: true,
      bvn,
      tx_ref: txRef,
      phonenumber: '',
      firstname: accountName.split(' ')[0] || accountName,
      lastname: accountName.split(' ').slice(1).join(' ') || '',
      narration: `DayFi — ${accountName}`,
    });

    const result = {
      accountNumber: flwData.account_number,
      bankName:      flwData.bank_name,
      accountName:   flwData.account_name || accountName,
    };

    await prisma.user.update({
      where: { id: req.user.id },
      data: { virtualAccountNumber: result.accountNumber, virtualAccountBank: result.bankName, virtualAccountName: result.accountName },
    });

    console.log(`✅ Virtual account created for user ${req.user.id}: ${result.accountNumber}`);
    return res.json(result);
  } catch (err) {
    console.error('POST /virtual-account error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/payments/flutterwave/init ─────────────────────────────────────

router.post('/flutterwave/init', authenticate, [
  body('amount').isFloat({ min: 100 }).withMessage('Minimum deposit is ₦100'),
  body('currency').optional().isString(),
  body('txRef').optional().isString().isLength({ min: 8, max: 120 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  if (!ensureFlw(res)) return;

  try {
    const amount   = Number(req.body.amount);
    const currency = (req.body.currency || 'NGN').toUpperCase();
    const txRef    = req.body.txRef || `dayfi-dep-${req.user.id}-${Date.now()}`;

    const existing = await prisma.flutterwavePayment.findUnique({ where: { txRef } });
    if (existing && existing.userId === req.user.id) {
      return res.json({ txRef: existing.txRef, paymentLink: existing.redirectUrl, status: existing.status });
    }

    const linkData = await flwRequest('/payments', 'POST', {
      tx_ref: txRef, amount, currency,
      redirect_url: process.env.FRONTEND_URL || 'https://dayfi.me',
      customer: { email: req.user.email, name: req.user.username || req.user.email },
      customizations: { title: 'DayFi Deposit', description: 'Top up your NGNT balance' },
    });

    const payment = await prisma.flutterwavePayment.create({
      data: {
        userId: req.user.id, txRef,
        flwRef: linkData?.id ? String(linkData.id) : null,
        type: 'deposit', fiatAmount: amount, currency,
        status: 'initiated', providerStatus: 'initiated',
        customerEmail: req.user.email,
        customerName:  req.user.username || req.user.email,
        redirectUrl:   linkData?.link || process.env.FRONTEND_URL,
      },
    });

    return res.json({ txRef: payment.txRef, paymentLink: linkData?.link, status: payment.status });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ─── POST /api/payments/flutterwave/verify ────────────────────────────────────

router.post('/flutterwave/verify', authenticate, [
  body('txRef').notEmpty(),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  if (!ensureFlw(res)) return;

  try {
    const { txRef } = req.body;
    const payment = await prisma.flutterwavePayment.findUnique({ where: { txRef } });
    if (!payment || payment.userId !== req.user.id) return res.status(404).json({ error: 'Payment not found' });

    const verify = await flwRequest(`/transactions/verify_by_reference?tx_ref=${encodeURIComponent(txRef)}`);
    const providerStatus = String(verify?.status || '').toLowerCase();
    const nextStatus = providerStatus === 'successful' ? 'successful' : providerStatus === 'failed' ? 'failed' : 'pending';

    const updated = await prisma.flutterwavePayment.update({
      where: { txRef },
      data: { status: nextStatus, providerStatus, providerMessage: verify?.processor_response || null, flwRef: verify?.flw_ref || payment.flwRef },
    });

    let settlement = null;
    if (nextStatus === 'successful' && payment.type === 'deposit') {
      const processed = await processDepositSuccess({
        userId: req.user.id, txRef,
        flwRef: verify?.flw_ref || payment.flwRef,
        amount: Number(verify?.amount || payment.fiatAmount),
        currency: payment.currency,
        providerStatus,
        providerMessage: verify?.processor_response || null,
      });
      settlement = processed.settlement;
    }

    return res.json({ txRef: updated.txRef, status: updated.status, providerStatus, amount: verify?.amount || payment.fiatAmount, currency: payment.currency, settlement });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ─── POST /api/payments/flutterwave/webhook ───────────────────────────────────

router.post('/flutterwave/webhook', async (req, res) => {
  try {
    if (!FLW_WEBHOOK_HASH) return res.status(503).json({ ok: false, message: 'Webhook hash not configured' });

    const signature = req.header('verif-hash') || req.header('x-flw-signature') || '';
    if (!signature || signature !== FLW_WEBHOOK_HASH) return res.status(401).json({ ok: false, message: 'Invalid webhook signature' });

    const event         = req.body?.event || '';
    const data          = req.body?.data  || {};
    const txRef         = data?.tx_ref || data?.txRef || data?.reference || data?.flw_ref;
    const providerStatus = String(data?.status || '').toLowerCase();
    const amount        = Number(data?.amount || 0);
    const currency      = data?.currency || 'NGN';
    const flwRef        = data?.flw_ref || data?.id || null;
    const accountNumber = data?.account_number || data?.meta?.account_number || null;
    const providerMessage = data?.processor_response || data?.narration || null;

    if (!txRef) return res.status(200).json({ ok: true, ignored: 'missing_reference' });
    if (!['charge.completed', 'charge.successful', 'transfer.completed'].includes(event))
      return res.status(200).json({ ok: true, ignored: 'unsupported_event' });
    if (!isSuccess(providerStatus)) return res.status(200).json({ ok: true, ignored: 'non_success_status' });

    let payment = await prisma.flutterwavePayment.findUnique({ where: { txRef } });
    let userId  = payment?.userId || null;

    if (!userId && accountNumber) {
      const user = await prisma.user.findFirst({ where: { virtualAccountNumber: String(accountNumber) }, select: { id: true } });
      userId = user?.id || null;
    }
    if (!userId) return res.status(200).json({ ok: true, ignored: 'user_not_found' });

    const processed = await processDepositSuccess({ userId, txRef, flwRef, amount, currency, providerStatus, providerMessage });
    return res.status(200).json({ ok: true, txRef, processed: processed.processed, settlement: processed.settlement || null });
  } catch (err) {
    console.error('Flutterwave webhook error:', err.message);
    return res.status(500).json({ ok: false, message: err.message });
  }
});

// ─── POST /api/payments/flutterwave/withdraw ──────────────────────────────────

router.post('/flutterwave/withdraw', authenticate, [
  body('ngntAmount').isFloat({ min: 1 }),
  body('bankCode').notEmpty(),
  body('accountNumber').notEmpty(),
  body('accountName').notEmpty(),
  body('idempotencyKey').optional().isString().isLength({ min: 8, max: 120 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  if (!ensureFlw(res)) return;

  try {
    const { ngntAmount, bankCode, accountNumber, accountName, idempotencyKey } = req.body;
    const txRef = idempotencyKey
      ? `dayfi-wd-${req.user.id}-${idempotencyKey}`
      : `dayfi-wd-${req.user.id}-${Date.now()}`;

    const existing = await prisma.flutterwavePayment.findUnique({ where: { txRef } });
    if (existing && existing.userId === req.user.id) return res.json({ txRef: existing.txRef, status: existing.status });

    const transfer = await flwRequest('/transfers', 'POST', {
      account_bank: bankCode,
      account_number: accountNumber,
      amount: Number(ngntAmount),
      currency: 'NGN',
      reference: txRef,
      narration: 'DayFi withdrawal',
      beneficiary_name: accountName,
      debit_currency: 'NGN',
    });

    const providerStatus = String(transfer?.status || 'pending').toLowerCase();
    const status = providerStatus === 'successful' ? 'successful' : providerStatus === 'failed' ? 'failed' : 'pending';

    const payment = await prisma.flutterwavePayment.create({
      data: {
        userId: req.user.id, txRef,
        flwRef: transfer?.id ? String(transfer.id) : null,
        type: 'withdrawal',
        fiatAmount: Number(ngntAmount),
        currency: 'NGN', status, providerStatus,
        idempotencyKey: idempotencyKey || null,
        bankCode, accountNumber, accountName,
        customerEmail: req.user.email,
        customerName:  req.user.username || req.user.email,
      },
    });

    return res.json({ txRef: payment.txRef, status: payment.status, providerReference: payment.flwRef });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ─── GET /api/payments/flutterwave/banks ──────────────────────────────────────

router.get('/flutterwave/banks', authenticate, async (_req, res) => {
  if (!ensureFlw(res)) return;
  try {
    const banks = await flwRequest('/banks/NG');
    const normalized = (banks || []).map(b => ({ code: String(b.code || ''), name: String(b.name || '') }));
    return res.json({ banks: normalized });
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// ─── POST /api/payments/flutterwave/resolve-account ───────────────────────────

router.post('/flutterwave/resolve-account', authenticate, [
  body('bankCode').notEmpty(),
  body('accountNumber').isLength({ min: 10, max: 10 }).withMessage('Account number must be 10 digits'),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  if (!ensureFlw(res)) return;
  try {
    const { bankCode, accountNumber } = req.body;
    const resolved = await flwRequest(
      `/accounts/resolve?account_number=${encodeURIComponent(accountNumber)}&account_bank=${encodeURIComponent(bankCode)}`
    );
    return res.json({ accountNumber, bankCode, accountName: resolved?.account_name || null });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;
