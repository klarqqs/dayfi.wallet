import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';

import authRoutes        from './routes/auth.js';
import walletRoutes      from './routes/wallet.js';
import userRoutes        from './routes/user.js';
import transactionRoutes from './routes/transactions.js';
import paymentsRoutes    from './routes/payments.js';
import sep10Routes       from './routes/sep10.js';
import sep24Routes       from './routes/sep24.js';
import sep38Routes       from './routes/sep38.js';
import tomlRoutes        from './routes/toml.js';
import { errorHandler }  from './middleware/errorHandler.js';

dotenv.config();

const app  = express();
app.set('trust proxy', 1);
const PORT    = process.env.PORT || 3001;
const NETWORK = process.env.STELLAR_NETWORK || 'mainnet';

// ─── Security ────────────────────────────────────────────────────────────────

app.use(helmet());
app.use(cors({
  origin: [
    process.env.FRONTEND_URL || 'https://dayfi.me',
    'http://localhost:3000',
    'http://localhost:5173',
    /\.dayfi\.me$/,
  ],
  credentials: true,
}));

const globalLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 300 });
const authLimiter   = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Too many auth attempts, try again later.' },
});
const sep10Limiter  = rateLimit({ windowMs: 60 * 1000, max: 30 });

app.use(globalLimiter);
app.use(express.json({ limit: '5mb' }));
app.use(express.urlencoded({ extended: true }));

// ─── SEP-01 ───────────────────────────────────────────────────────────────────

app.use('/.well-known', tomlRoutes);

// ─── Health ───────────────────────────────────────────────────────────────────

app.get('/health', (_, res) => res.json({
  status: 'ok',
  service: 'dayfi-backend',
  version: '1.0.0',
  network: NETWORK,
  timestamp: new Date().toISOString(),
}));

// ─── App API ──────────────────────────────────────────────────────────────────

app.use('/api/auth',         authLimiter, authRoutes);
app.use('/api/wallet',       walletRoutes);
app.use('/api/user',         userRoutes);
app.use('/api/transactions', transactionRoutes);
app.use('/api/payments',     paymentsRoutes);

// ─── SEP Routes ───────────────────────────────────────────────────────────────

app.use('/sep10', sep10Limiter, sep10Routes);
app.use('/sep24', sep24Routes);
app.use('/sep38', sep38Routes);

// ─── Public Username Resolution ───────────────────────────────────────────────

app.get('/resolve/:username', async (req, res) => {
  const { resolveUsername } = await import('./services/walletService.js');
  try {
    const result = await resolveUsername(req.params.username);
    if (!result) return res.status(404).json({ error: 'Username not found' });
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.use(errorHandler);

app.listen(PORT, () => {
  const label = NETWORK.toUpperCase();
  console.log(`
  ╔════════════════════════════════════════╗
  ║          DAYFI BACKEND v1.0            ║
  ║  Mode    : PRODUCTION                  ║
  ║  Port    : ${PORT.toString().padEnd(28)}║
  ║  Network : ${label.padEnd(28)}║
  ║  Status  : LIVE & MONITORING           ║
  ╚════════════════════════════════════════╝
  `);
});

export default app;