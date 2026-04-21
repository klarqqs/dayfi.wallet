// src/services/swapService.js
// Swap routing:
//   Same-chain Stellar swaps  → Stellar DEX (PathPaymentStrictReceive)
//   EVM token swaps           → 0x Protocol API
//   Cross-chain swaps         → Changelly API

import StellarSdk from "@stellar/stellar-sdk";
import { PrismaClient } from "@prisma/client";
import crypto from "crypto";

const prisma = new PrismaClient();

const isTestnet = process.env.STELLAR_NETWORK !== "mainnet";
const server = new StellarSdk.Horizon.Server(
  process.env.STELLAR_HORIZON_URL || "https://horizon-testnet.stellar.org",
);
const networkPassphrase = isTestnet
  ? StellarSdk.Networks.TESTNET
  : StellarSdk.Networks.PUBLIC;

// ─── Asset definitions ────────────────────────────────────────────────────────

const USDC_ISSUER =
  process.env.USDC_ISSUER ||
  (isTestnet
    ? "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
    : "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN");
const GOLD_ISSUER =
  process.env.GOLD_ISSUER ||
  "GDBE77Z976GZ66WQSBCYI3S7A67T5OVCB57FPR35CCV72L7DQXNGA476";

const STELLAR_ASSETS = {
  XLM: StellarSdk.Asset.native(),
  USDC: new StellarSdk.Asset("USDC", USDC_ISSUER),
  GOLD: new StellarSdk.Asset("GOLD", GOLD_ISSUER),
};

// EVM token addresses (mainnet)
const EVM_TOKENS = {
  USDC_ethereum: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  USDC_arbitrum: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
  USDC_polygon: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
  ETH_ethereum: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", // native ETH sentinel
};

// Encryption
const ALGORITHM = "aes-256-gcm";
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || "a".repeat(64),
  "hex",
);

function decrypt(encText) {
  const [ivHex, tagHex, enc] = encText.split(":");
  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    ENCRYPTION_KEY,
    Buffer.from(ivHex, "hex"),
  );
  decipher.setAuthTag(Buffer.from(tagHex, "hex"));
  let dec = decipher.update(enc, "hex", "utf8");
  dec += decipher.final("utf8");
  return dec;
}

// ─── SWAP CATEGORY DETECTION ─────────────────────────────────────────────────

function getSwapCategory(fromAsset, fromNetwork, toAsset, toNetwork) {
  const sameChain = fromNetwork === toNetwork;
  const bothStellar = fromNetwork === "stellar" && toNetwork === "stellar";
  const bothEVM =
    ["ethereum", "arbitrum", "polygon", "avalanche"].includes(fromNetwork) &&
    ["ethereum", "arbitrum", "polygon", "avalanche"].includes(toNetwork);

  if (bothStellar) return "stellar_dex";
  if (bothEVM && sameChain) return "evm_0x";
  return "cross_chain_changelly";
}

// ─── 1. STELLAR DEX SWAP ─────────────────────────────────────────────────────

async function getStellarSwapQuote(fromAsset, toAsset, sellAmount) {
  const from = STELLAR_ASSETS[fromAsset];
  const to = STELLAR_ASSETS[toAsset];
  if (!from || !to)
    throw new Error(`Stellar DEX: unsupported pair ${fromAsset}/${toAsset}`);

  try {
    const paths = await server
      .strictSendPaths(from, sellAmount.toFixed(7), [to])
      .call();

    if (!paths.records.length)
      throw new Error("No liquidity path found on Stellar DEX");

    const best = paths.records[0];
    return {
      provider: "stellar_dex",
      fromAsset,
      toAsset,
      fromAmount: parseFloat(sellAmount),
      toAmount: parseFloat(best.destination_amount),
      rate: parseFloat(best.destination_amount) / parseFloat(sellAmount),
      fee: 0.00001, // ~1 stroop
      feeCurrency: "XLM",
      path: best.path,
      expiresAt: new Date(Date.now() + 30_000).toISOString(), // 30s
    };
  } catch (err) {
    throw new Error(`Stellar DEX quote failed: ${err.message}`);
  }
}

async function executeStellarSwap({
  userId,
  fromAsset,
  toAsset,
  fromAmount,
  minReceive,
  path,
}) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user?.stellarPublicKey || !user?.stellarSecretKey)
    throw new Error("Stellar wallet not found");

  const keypair = StellarSdk.Keypair.fromSecret(decrypt(user.stellarSecretKey));
  const account = await server.loadAccount(user.stellarPublicKey);

  const from = STELLAR_ASSETS[fromAsset];
  const to = STELLAR_ASSETS[toAsset];

  const tx = new StellarSdk.TransactionBuilder(account, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase,
  })
    .addOperation(
      StellarSdk.Operation.pathPaymentStrictSend({
        sendAsset: from,
        sendAmount: fromAmount.toFixed(7),
        destination: user.stellarPublicKey, // send to self (swap)
        destAsset: to,
        destMin: (minReceive * 0.995).toFixed(7), // 0.5% slippage tolerance
        path: path || [],
      }),
    )
    .setTimeout(30)
    .build();
  tx.sign(keypair);
  const result = await server.submitTransaction(tx);

  await prisma.transaction.upsert({
    where: { stellarTxHash: result.hash },
    update: {},
    create: {
      userId,
      type: "swap",
      status: "confirmed",
      amount: fromAmount,
      asset: fromAsset,
      network: "stellar",
      fromAddress: user.stellarPublicKey,
      toAddress: user.stellarPublicKey,
      stellarTxHash: result.hash,
      isSwap: true,
      swapFromAsset: fromAsset,
      swapToAsset: toAsset,
      swapToAmount: minReceive,
    },
  });

  return {
    hash: result.hash,
    provider: "stellar_dex",
    fromAsset,
    toAsset,
    fromAmount,
    swapToAmount: minReceive,
  };
}

// ─── 2. 0x PROTOCOL (EVM swaps) ──────────────────────────────────────────────

const ZERO_X_BASE = "https://api.0x.org";
const ZERO_X_CHAINS = {
  ethereum: 1,
  arbitrum: 42161,
  polygon: 137,
  avalanche: 43114,
};

async function get0xQuote({
  fromToken,
  toToken,
  sellAmount,
  network,
  takerAddress,
}) {
  const chainId = ZERO_X_CHAINS[network];
  if (!chainId) throw new Error(`0x not supported on ${network}`);

  const params = new URLSearchParams({
    chainId: chainId.toString(),
    sellToken: fromToken,
    buyToken: toToken,
    sellAmount: sellAmount.toString(),
    taker: takerAddress,
  });

  const res = await fetch(`${ZERO_X_BASE}/swap/permit2/quote?${params}`, {
    headers: {
      "0x-api-key": process.env.ZERO_X_API_KEY || "",
      "0x-version": "v2",
    },
  });

  if (!res.ok) {
    const err = await res.json();
    throw new Error(`0x quote failed: ${err.reason || JSON.stringify(err)}`);
  }

  return res.json();
}

// ─── 3. CHANGELLY (cross-chain swaps) ────────────────────────────────────────

const CHANGELLY_API = "https://api.changelly.com/v2";

async function changellyRequest(method, params) {
  const id = Date.now().toString();
  const body = JSON.stringify({ jsonrpc: "2.0", id, method, params });

  const signature = crypto
    .createHmac("sha512", process.env.CHANGELLY_SECRET_KEY || "")
    .update(body)
    .digest("hex");

  const res = await fetch(CHANGELLY_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "api-key": process.env.CHANGELLY_API_KEY || "",
      sign: signature,
    },
    body,
  });

  const data = await res.json();
  if (data.error) throw new Error(`Changelly error: ${data.error.message}`);
  return data.result;
}

async function getChangellyQuote({ fromCurrency, toCurrency, fromAmount }) {
  const [minAmount, exchangeAmount] = await Promise.all([
    changellyRequest("getMinAmount", {
      from: fromCurrency.toLowerCase(),
      to: toCurrency.toLowerCase(),
    }),
    changellyRequest("getExchangeAmount", {
      from: fromCurrency.toLowerCase(),
      to: toCurrency.toLowerCase(),
      amount: fromAmount.toString(),
    }),
  ]);

  return {
    provider: "changelly",
    fromAsset: fromCurrency,
    toAsset: toCurrency,
    fromAmount,
    toAmount: parseFloat(
      Array.isArray(exchangeAmount)
        ? exchangeAmount[0]?.result
        : exchangeAmount,
    ),
    minAmount: parseFloat(minAmount),
    rate:
      parseFloat(
        Array.isArray(exchangeAmount)
          ? exchangeAmount[0]?.result
          : exchangeAmount,
      ) / fromAmount,
    fee: parseFloat(fromAmount) * 0.005, // ~0.5% Changelly fee
    feeCurrency: fromCurrency,
    expiresAt: new Date(Date.now() + 300_000).toISOString(), // 5 min
  };
}

async function executeChangellySwap({
  fromCurrency,
  toCurrency,
  fromAmount,
  toAddress,
  refundAddress,
}) {
  const result = await changellyRequest("createTransaction", {
    from: fromCurrency.toLowerCase(),
    to: toCurrency.toLowerCase(),
    amount: fromAmount.toString(),
    address: toAddress,
    refundAddress,
  });

  return {
    provider: "changelly",
    id: result.id,
    fromCurrency,
    toCurrency,
    fromAmount,
    toAmount: parseFloat(result.amountExpectedTo),
    depositAddress: result.payinAddress, // send your coins HERE
    depositMemo: result.payinExtraId, // memo/tag if required
    receiveAddress: result.payoutAddress,
    expiresAt: result.validUntil,
    status: result.status,
  };
}

// ─── UNIFIED QUOTE API ────────────────────────────────────────────────────────

export async function getSwapQuote({
  fromAsset,
  fromNetwork,
  toAsset,
  toNetwork,
  fromAmount,
  userId,
}) {
  const category = getSwapCategory(fromAsset, fromNetwork, toAsset, toNetwork);

  switch (category) {
    case "stellar_dex":
      return await getStellarSwapQuote(fromAsset, toAsset, fromAmount);

    case "evm_0x": {
      const user = await prisma.user.findUnique({ where: { id: userId } });
      const fromToken = EVM_TOKENS[`${fromAsset}_${fromNetwork}`];
      const toToken = EVM_TOKENS[`${toAsset}_${toNetwork}`];
      if (!fromToken || !toToken) throw new Error("Token not found for 0x");
      // Amount in wei (assuming 6 decimals for USDC)
      const sellAmount = BigInt(Math.round(fromAmount * 1e6)).toString();
      const quote = await get0xQuote({
        fromToken,
        toToken,
        sellAmount,
        network: fromNetwork,
        takerAddress: user.evmPublicKey,
      });
      return {
        provider: "0x",
        fromAsset,
        toAsset,
        fromAmount,
        toAmount: parseFloat(quote.buyAmount) / 1e6,
        rate: parseFloat(quote.buyAmount) / parseFloat(quote.sellAmount),
        gas: quote.gas,
        expiresAt: new Date(Date.now() + 30_000).toISOString(),
        rawQuote: quote,
      };
    }

    case "cross_chain_changelly":
      return await getChangellyQuote({
        fromCurrency: fromAsset,
        toCurrency: toAsset,
        fromAmount,
      });

    default:
      throw new Error("No swap route available");
  }
}

// ─── UNIFIED EXECUTE API ──────────────────────────────────────────────────────

export async function executeSwap({
  userId,
  fromAsset,
  fromNetwork,
  toAsset,
  toNetwork,
  fromAmount,
  quoteData,
}) {
  const category = getSwapCategory(fromAsset, fromNetwork, toAsset, toNetwork);

  switch (category) {
    case "stellar_dex":
      return await executeStellarSwap({
        userId,
        fromAsset,
        toAsset,
        fromAmount,
        minReceive: quoteData?.toAmount,
        path: quoteData?.path,
      });

    case "evm_0x":
      throw new Error(
        "EVM swap execution via 0x requires frontend permit2 signing — use rawQuote.transaction",
      );

    case "cross_chain_changelly": {
      const user = await prisma.user.findUnique({ where: { id: userId } });
      const toAddress =
        toNetwork === "stellar"
          ? user.stellarPublicKey
          : toNetwork === "bitcoin"
            ? user.btcPublicKey
            : toNetwork === "solana"
              ? user.solanaPublicKey
              : user.evmPublicKey;

      const refundAddress =
        fromNetwork === "stellar"
          ? user.stellarPublicKey
          : fromNetwork === "bitcoin"
            ? user.btcPublicKey
            : user.evmPublicKey;

      return await executeChangellySwap({
        fromCurrency: fromAsset,
        toCurrency: toAsset,
        fromAmount,
        toAddress,
        refundAddress,
      });
    }

    default:
      throw new Error("No swap execution route");
  }
}

// ─── Swap route info ──────────────────────────────────────────────────────────

export function getSwapRouteInfo(fromAsset, fromNetwork, toAsset, toNetwork) {
  const category = getSwapCategory(fromAsset, fromNetwork, toAsset, toNetwork);
  return {
    category,
    provider:
      category === "stellar_dex"
        ? "Stellar DEX"
        : category === "evm_0x"
          ? "0x Protocol"
          : "Changelly",
    estimatedTime:
      category === "stellar_dex"
        ? "~5 seconds"
        : category === "evm_0x"
          ? "~30 seconds"
          : "~10-30 minutes",
    feeTier:
      category === "stellar_dex"
        ? "Very low"
        : category === "evm_0x"
          ? "Low–Medium"
          : "Medium (0.5%)",
  };
}
