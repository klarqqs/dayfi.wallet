import express from 'express';
import { body, validationResult } from 'express-validator';
import { authenticate } from '../middleware/auth.js';
import {
  getWalletBalances,
  sendAsset,
  swapAssets,
  getStellarTransactions,
  resolveUsername,
  sendFromMasterWallet,
  syncBlockchainTransactions,
  ISSUERS,
  SUPPORTED_ASSETS,
} from '../services/walletService.js';
import StellarSdk from "@stellar/stellar-sdk";

const router = express.Router();

// ─── Asset Configuration with Emojis ─────────────────────────────────────────

const ASSET_CONFIG = {
  USDC: {
    name: 'USD Coin',
    emoji: '💵',
    description: 'Regulated US Dollar stablecoin',
    regulated: true,
    issuers: [
      {
        key: 'stellar_usdc',
        label: 'Circle (Stellar)',
        description: 'Issued by Circle on Stellar Network',
        emoji: '⭐',
      },
    ],
  },
  NGNT: {
    name: 'Nigerian Naira Token',
    emoji: '🇳🇬',
    description: 'NGN-backed stablecoin on Stellar',
    regulated: true,
    issuers: [
      {
        key: 'stellar_ngnt',
        label: 'AZA Finance (Stellar)',
        description: 'Issued by AZA Finance on Stellar Network',
        emoji: '⭐',
      },
    ],
  },
  XLM: {
    name: 'Stellar Lumens',
    emoji: '🌟',
    description: 'Native Stellar asset',
    regulated: false,
    issuers: [
      {
        key: 'stellar_xlm',
        label: 'Stellar',
        description: 'Native Stellar Network token',
        emoji: '⭐',
      },
    ],
  },
};

// ─── Shared Price Cache ──────────────────────────────────────────────────────

let _priceCache = null;
let _priceCacheTime = 0;
const PRICE_CACHE_TTL = 30 * 1000;

async function getLivePrices() {
  const now = Date.now();
  if (_priceCache && (now - _priceCacheTime) < PRICE_CACHE_TTL) return _priceCache;
  try {
    // Fetch prices from CoinGecko (free API)
    const res  = await fetch('https://api.coingecko.com/api/v3/simple/price?ids=usd-coin,stellar,meld-gold&vs_currencies=usd');
    const data = await res.json();
    _priceCache = {
      USDC: data['usd-coin']?.usd ?? 1.0,
      XLM:  data['stellar']?.usd  ?? 0.16,
      NGNT: 0.00065, // ~1 NGN in USD (fixed peg, not on CoinGecko)
    };
    _priceCacheTime = now;
    return _priceCache;
  } catch {
    return { USDC: 1.0, XLM: 0.16, NGNT: 0.00065 };
  }
}

// ─── GET /api/wallet/assets ───────────────────────────────────────────────────

router.get('/assets', authenticate, (req, res) => {
  const assets = Object.entries(ASSET_CONFIG).map(([code, config]) => ({
    code,
    name: config.name,
    emoji: config.emoji,
    description: config.description,
    regulated: config.regulated,
    network: 'stellar',
    issuers: config.issuers,
  }));

  res.json({
    network: 'stellar',
    assets,
  });
});

// ─── GET /api/wallet/networks ─────────────────────────────────────────────────

router.get('/networks', authenticate, (req, res) => {
  // For now: only Stellar is supported
  // Assets available on Stellar
  const assets = {
    'USDC': ['stellar'],
    'NGNT': ['stellar'],
    'XLM': ['stellar'],
  };

  // Network configuration
  const networks = {
    'stellar': {
      name: 'Stellar Network',
      emoji: '⭐',
      description: 'Fast, low-cost payments on Stellar',
      active: true,
    },
  };

  res.json({
    assets,
    networks,
  });
});

// ─── GET /api/wallet/swap-quote ───────────────────────────────────────────────

router.get('/swap-quote', authenticate, async (req, res) => {
  const { from, to, amount } = req.query;
  if (!from || !to || !amount) return res.status(400).json({ error: 'Missing params' });

  console.log(`🔵 QUOTE REQUEST: ${from} -> ${to} | Amount: ${amount}`);

  try {
    const { server } = await import('../services/walletService.js');
    
    // 1. Try Stellar Horizon for real DEX path
    try {
      const paths = await server.strictSendPaths(
        from === 'XLM' ? StellarSdk.Asset.native() : new StellarSdk.Asset(from, ISSUERS[from]),
        amount,
        [to === 'XLM' ? StellarSdk.Asset.native() : new StellarSdk.Asset(to, ISSUERS[to])]
      ).call();

      if (paths.records.length) {
        const best = paths.records[0];
        console.log(`✅ QUOTE FOUND: ${amount} ${from} = ${best.destination_amount} ${to}`);
        return res.json({
          fromAsset: from,
          toAsset: to,
          fromAmount: parseFloat(amount),
          buy_amount: parseFloat(best.destination_amount).toFixed(6),
          price: (parseFloat(best.destination_amount) / parseFloat(amount)).toFixed(6),
          source: 'stellar_dex',
        });
      }
    } catch (e) {
      console.warn(`⚠️  Horizon quote failed for ${from}->${to}:`, e.message);
    }

    // 2. Fallback to Price API
    const PRICES = await getLivePrices();
    const toAmt = (parseFloat(amount) * (PRICES[from] || 1)) / (PRICES[to] || 1);

    console.log(`✅ QUOTE FALLBACK: ${amount} ${from} = ${toAmt.toFixed(6)} ${to}`);
    return res.json({
      fromAsset: from,
      toAsset: to,
      fromAmount: parseFloat(amount),
      buy_amount: toAmt.toFixed(6),
      price: (toAmt / parseFloat(amount)).toFixed(6),
      source: 'fallback',
    });
  } catch (err) {
    console.error(`❌ QUOTE ERROR:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/wallet/swap ────────────────────────────────────────────────────

router.post('/swap', authenticate, [
  body('fromAsset').isIn(SUPPORTED_ASSETS),
  body('toAsset').isIn(SUPPORTED_ASSETS),
  body('amount').isFloat({ min: 0.000001 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  const { fromAsset, toAsset, amount } = req.body;
  if (fromAsset === toAsset) return res.status(400).json({ error: 'Same asset' });

  console.log(`🔵 SWAP INITIATED: ${req.user.id} | ${fromAsset} -> ${toAsset} | Amount: ${amount}`);

  try {
    const result = await swapAssets(req.user.id, fromAsset, toAsset, parseFloat(amount));
    console.log(`✅ SWAP SUCCESS: ${result.hash}`);
    res.json({ success: true, transaction: result });
  } catch (err) {
    console.error(`❌ SWAP FAILED for user ${req.user.id}:`, err.message);
    console.error('Full error:', err);
    
    // User-friendly error messages
    let userMessage = err.message || 'Swap failed';
    if (err.message.includes('no path') || err.message.includes('No liquidity')) {
      userMessage = `Not enough liquidity to swap ${fromAsset} to ${toAsset}. Try a smaller amount.`;
    } else if (err.message.includes('trustline')) {
      userMessage = 'Trustline not ready yet. Please wait a moment and try again.';
    } else if (err.message.includes('insufficient') || err.message.includes('not enough')) {
      userMessage = `Insufficient ${fromAsset} balance`;
    } else if (err.message.includes('Stellar wallet not found')) {
      userMessage = 'Wallet not initialized. Please reload the app.';
    }
    res.status(400).json({ error: userMessage });
  }
});

// ─── GET /api/wallet/balance ──────────────────────────────────────────────────

router.get('/balance', authenticate, async (req, res) => {
  try {
    const balances = await getWalletBalances(req.user.stellarPublicKey);
    const PRICES = await getLivePrices();

    const balancesUSD = Object.fromEntries(
      Object.entries(balances).map(([asset, amount]) => [
        asset,
        parseFloat((amount * (PRICES[asset] || 0)).toFixed(2)),
      ])
    );

    const totalUSD = Object.values(balancesUSD).reduce((sum, v) => sum + v, 0);

    res.json({
      address: req.user.stellarPublicKey,
      balances,
      balancesUSD,
      totalUSD: parseFloat(totalUSD.toFixed(2)),
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── GET /api/wallet/address ──────────────────────────────────────────────────

router.get('/address', authenticate, (req, res) => {
  res.json({
    stellarAddress: req.user.stellarPublicKey,
    dayfiUsername: `${req.user.username}@dayfi.me`,
    assets: [
      { code: 'USDC', name: 'USD Coin', issuer: ISSUERS.USDC },
      { code: 'NGNT', name: 'Nigerian Naira Token', issuer: ISSUERS.NGNT },
    ],
  });
});

// ─── POST /api/wallet/send ────────────────────────────────────────────────────

router.post('/send', authenticate, [
  body('to').notEmpty(),
  body('amount').isFloat({ min: 0.000001 }),
  body('asset').isIn(SUPPORTED_ASSETS),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  let { to, amount, asset, memo } = req.body;
  try {
    const result = await sendAsset(req.user.id, to, parseFloat(amount), asset, memo);
    res.json({ success: true, transaction: result });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ─── GET /api/wallet/stellar-history ─────────────────────────────────────────

router.get('/stellar-history', authenticate, async (req, res) => {
  try {
    const history = await getStellarTransactions(req.user.stellarPublicKey);
    res.json({ transactions: history });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── GET /api/wallet/check-trustlines ────────────────────────────────────────

router.get('/check-trustlines', authenticate, async (req, res) => {
  try {
    const account = await (await import('../services/walletService.js')).server.loadAccount(
      req.user.stellarPublicKey
    );

    const balances = account.balances || [];
    const hasTrustlines = {
      USDC: balances.some(b => b.asset_code === 'USDC'),
      NGNT: balances.some(b => b.asset_code === 'NGNT'),
      XLM: true,
    };

    const allReady = Object.values(hasTrustlines).every(v => v);

    res.json({
      ready: allReady,
      trustlines: hasTrustlines,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─── POST /api/wallet/admin/send (Master Wallet) ─────────────────────────────

router.post('/admin/send', authenticate, [
  body('recipientAddress').notEmpty().isLength({ min: 56, max: 56 }),
  body('amount').isFloat({ min: 0.000001 }),
  body('memo').optional().isString().isLength({ max: 28 }),
], async (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });

  // Simple admin check: verify user is admin (you can add more sophisticated checks)
  const isAdmin = process.env.ADMIN_EMAILS?.split(',').includes(req.user.email);
  if (!isAdmin) {
    return res.status(403).json({ error: 'Only admins can send from master wallet' });
  }

  const { recipientAddress, amount, memo } = req.body;
  try {
    const result = await sendFromMasterWallet(recipientAddress, parseFloat(amount), memo);
    res.json({ success: true, transaction: result });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ─── POST /api/wallet/test-funding (Testing only - auto-fund user) ────────────

router.post('/test-funding', authenticate, async (req, res) => {
  try {
    const fundingAmount = 1.0;
    const userAddress = req.user.stellarPublicKey;

    if (!userAddress) {
      return res.status(400).json({ error: 'User wallet not created' });
    }

    const result = await sendFromMasterWallet(userAddress, fundingAmount, 'Test funding');
    res.json({
      success: true,
      message: `✅ Funded ${fundingAmount} XLM to your wallet`,
      transaction: result,
    });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// ─── Sync transactions from blockchain ────────────────────────────────────────

router.post('/sync-transactions', authenticate, async (req, res) => {
  try {
    const result = await syncBlockchainTransactions(req.user.id);
    res.json({
      success: true,
      message: `✅ Synced ${result.synced} transactions from blockchain`,
      synced: result.synced,
    });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

export default router;