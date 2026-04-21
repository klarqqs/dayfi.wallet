import StellarSdk from "@stellar/stellar-sdk";
import StellarHDWallet from "stellar-hd-wallet";
import crypto from "crypto";
import { PrismaClient } from "@prisma/client";
import {
  sendPaymentSentEmail,
  sendPaymentReceivedEmail,
  sendSwapCompleteEmail,
} from "./emailService.js";

const prisma = new PrismaClient();

const isTestnet = process.env.STELLAR_NETWORK !== "mainnet";
const server = new StellarSdk.Horizon.Server(
  process.env.STELLAR_HORIZON_URL ||
    (isTestnet
      ? "https://horizon-testnet.stellar.org"
      : "https://horizon.stellar.org"),
);
const networkPassphrase = isTestnet
  ? StellarSdk.Networks.TESTNET
  : StellarSdk.Networks.PUBLIC;

// ─── Issuers ──────────────────────────────────────────────────────────────────

export const ISSUERS = {
  USDC:
    process.env.USDC_ISSUER ||
    (isTestnet
      ? "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"
      : "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"),
  // TODO: Fix GOLD issuer - currently invalid
  // GOLD:
  //   process.env.GOLD_ISSUER ||
  //   (isTestnet
  //     ? "GDPJALI4AZKUU2W426U5WKMAT6CN3AJRPIIRYR2YM54TL2GDWO5O2MZM"
  //     : "GDBE77Z976GZ66WQSBCYI3S7A67T5OVCB57FPR35CCV72L7DQXNGA476"),
};

export const ASSETS = {
  USDC: new StellarSdk.Asset("USDC", ISSUERS.USDC),
  // GOLD: new StellarSdk.Asset("GOLD", ISSUERS.GOLD),
  XLM: StellarSdk.Asset.native(),
};

export const SUPPORTED_ASSETS = ["USDC", "XLM"]; // Temporarily removed GOLD

// ─── Encryption ───────────────────────────────────────────────────────────────

const ALGORITHM = "aes-256-gcm";
const ENCRYPTION_KEY = Buffer.from(
  process.env.WALLET_ENCRYPTION_KEY || "a".repeat(64),
  "hex",
);

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);
  let enc = cipher.update(text, "utf8", "hex");
  enc += cipher.final("hex");
  return `${iv.toString("hex")}:${cipher.getAuthTag().toString("hex")}:${enc}`;
}

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

// ─── Setup trustlines for user (after wallet is created) ─────────────────────

export async function setupUserTrustlines(user) {
  if (!user.stellarSecretKey) {
    console.warn(
      `⚠️  User ${user.id} has no secret key. Skipping trustline setup.`,
    );
    return false;
  }

  try {
    const secret = decrypt(user.stellarSecretKey);
    const keypair = StellarSdk.Keypair.fromSecret(secret);
    await addAllTrustlines(keypair);
    console.log(`✅ Trustlines added for ${user.stellarPublicKey}`);
    return true;
  } catch (err) {
    console.error(
      `❌ Trustline setup failed for user ${user.id}:`,
      err.message,
    );
    return false;
  }
}

// ─── Wallet creation (BIP-39, SEP-0005) ──────────────────────────────────────

export async function createStellarWallet() {
  const mnemonic = StellarHDWallet.generateMnemonic({ entropyBits: 128 });
  const wallet = StellarHDWallet.fromMnemonic(mnemonic);
  const keypair = wallet.getKeypair(0);
  const publicKey = keypair.publicKey();

  if (isTestnet) {
    try {
      const res = await fetch(
        `https://friendbot.stellar.org?addr=${encodeURIComponent(publicKey)}`,
      );
      if (res.ok) {
        console.log(`✅ Testnet funded: ${publicKey}`);
        await new Promise((r) => setTimeout(r, 3000));
        await addAllTrustlines(keypair);
      }
    } catch (err) {
      console.warn("Friendbot error:", err.message);
    }
  }

  return {
    publicKey,
    encryptedSecretKey: encrypt(keypair.secret()),
    encryptedMnemonic: encrypt(mnemonic),
  };
}

// ─── Trustlines ───────────────────────────────────────────────────────────────

export async function addAllTrustlines(keypair) {
  try {
    const account = await server.loadAccount(keypair.publicKey());
    const txBuilder = new StellarSdk.TransactionBuilder(account, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase,
    });

    // Add trustlines for all supported assets
    txBuilder
      .addOperation(
        StellarSdk.Operation.changeTrust({
          asset: ASSETS.USDC,
          limit: "1000000",
        }),
      )
      // TODO: Add GOLD trustline back once issuer is fixed
      // .addOperation(
      //   StellarSdk.Operation.changeTrust({
      //     asset: ASSETS.GOLD,
      //     limit: "1000000",
      //   })
      // )
      .setTimeout(30);

    const tx = txBuilder.build();
    tx.sign(keypair);
    const result = await server.submitTransaction(tx);
    return result;
  } catch (err) {
    console.error("Trustline error:", err.message);
    throw err;
  }
}

// ─── Balances ─────────────────────────────────────────────────────────────────

export async function getWalletBalances(publicKey) {
  try {
    const horizonBase =
      process.env.STELLAR_HORIZON_URL ||
      (isTestnet
        ? "https://horizon-testnet.stellar.org"
        : "https://horizon.stellar.org");

    const res = await fetch(`${horizonBase}/accounts/${publicKey}`, {
      headers: { "Cache-Control": "no-cache", Pragma: "no-cache" },
    });

    if (res.status === 404) return { USDC: 0, XLM: 0 };
    const account = await res.json();
    const balances = { USDC: 0, XLM: 0 };

    for (const b of account.balances) {
      if (b.asset_type === "native") {
        balances.XLM = parseFloat(b.balance);
      } else if (b.asset_code === "USDC" && b.asset_issuer === ISSUERS.USDC) {
        balances.USDC = parseFloat(b.balance);
      }
      // TODO: Add GOLD balance tracking back once issuer is fixed
      // else if (b.asset_code === "GOLD" && b.asset_issuer === ISSUERS.GOLD) {
      //   balances.GOLD = parseFloat(b.balance);
      // }
    }
    return balances;
  } catch (err) {
    return { USDC: 0, XLM: 0 };
  }
}

// ─── Live prices ─────────────────────────────────────────────────────────────

async function getLivePrices() {
  try {
    const res = await fetch(
      "https://api.coingecko.com/api/v3/simple/price?ids=usd-coin,stellar&vs_currencies=usd",
    );
    const data = await res.json();
    return {
      XLM: data["stellar"]?.usd ?? 0.169,
      USDC: data["usd-coin"]?.usd ?? 1.0,
    };
  } catch {
    return { XLM: 0.169, USDC: 1.0 };
  }
}

// ─── Mnemonic ─────────────────────────────────────────────────────────────────

export async function getMnemonic(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user?.encryptedMnemonic) throw new Error("No mnemonic found");
  return decrypt(user.encryptedMnemonic);
}

// ─── Mark backed up ───────────────────────────────────────────────────────────

export async function markAsBackedUp(userId) {
  return prisma.user.update({
    where: { id: userId },
    data: { isBackedUp: true },
  });
}

// ─── Send ─────────────────────────────────────────────────────────────────────

export async function sendAsset(
  fromUserId,
  toAddress,
  amount,
  assetCode,
  memo = "",
) {
  const asset =
    assetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[assetCode];
  if (!asset) throw new Error(`Unsupported asset: ${assetCode}`);

  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.stellarPublicKey || !sender?.stellarSecretKey)
    throw new Error("Stellar wallet not found");

  const keypair = StellarSdk.Keypair.fromSecret(
    decrypt(sender.stellarSecretKey),
  );
  let destinationPublicKey = toAddress;
  let destinationUsername = null;

  if (!/^G[A-Z0-9]{55}$/.test(toAddress)) {
    const username = toAddress
      .replace("@dayfi.me", "")
      .replace("@", "")
      .toLowerCase();
    const recipient = await prisma.user.findUnique({ where: { username } });
    if (!recipient?.stellarPublicKey) throw new Error(`@${username} not found`);
    destinationPublicKey = recipient.stellarPublicKey;
    destinationUsername = username;
  }

  const senderAccount = await server.loadAccount(sender.stellarPublicKey);
  const txBuilder = new StellarSdk.TransactionBuilder(senderAccount, {
    fee: StellarSdk.BASE_FEE,
    networkPassphrase,
  });

  let destExists = true;
  try {
    await server.loadAccount(destinationPublicKey);
  } catch {
    destExists = false;
  }

  if (!destExists) {
    txBuilder.addOperation(
      StellarSdk.Operation.createAccount({
        destination: destinationPublicKey,
        startingBalance: "1",
      }),
    );
  } else {
    txBuilder.addOperation(
      StellarSdk.Operation.payment({
        destination: destinationPublicKey,
        asset,
        amount: amount.toString(),
      }),
    );
  }

  if (memo) txBuilder.addMemo(StellarSdk.Memo.text(memo.substring(0, 28)));

  const tx = txBuilder.setTimeout(30).build();
  tx.sign(keypair);
  const result = await server.submitTransaction(tx);

  const txData = {
    userId: fromUserId,
    type: "send",
    status: "confirmed",
    amount: parseFloat(amount),
    asset: assetCode,
    network: "stellar",
    fromAddress: sender.stellarPublicKey,
    toAddress: destinationPublicKey,
    toUsername: destinationUsername,
    stellarTxHash: result.hash,
    memo: memo || null,
  };

  await prisma.transaction.create({ data: txData });

  // Record receive transaction for recipient (if it's a dayfi user)
  if (destinationUsername) {
    const recipient = await prisma.user.findUnique({
      where: { username: destinationUsername },
    });
    if (recipient?.id) {
      await prisma.transaction.create({
        data: {
          userId: recipient.id,
          type: "receive",
          status: "confirmed",
          amount: parseFloat(amount),
          asset: assetCode,
          network: "stellar",
          fromAddress: sender.stellarPublicKey,
          toAddress: destinationPublicKey,
          toUsername: sender.username || null,
          stellarTxHash: result.hash,
          memo: memo || null,
        },
      });
    }
  }

  // Send confirmation emails
  try {
    // Email to sender
    await sendPaymentSentEmail(
      sender.email,
      destinationUsername || destinationPublicKey,
      amount,
      assetCode,
      memo,
    );

    // Email to recipient (if it's a dayfi user)
    if (destinationUsername) {
      const recipient = await prisma.user.findUnique({
        where: { username: destinationUsername },
      });
      if (recipient?.email) {
        await sendPaymentReceivedEmail(
          recipient.email,
          sender.username || "Someone",
          amount,
          assetCode,
          memo,
        );
      }
    }
  } catch (err) {
    console.warn("⚠️  Transaction email failed:", err.message);
  }

  return { hash: result.hash, amount, asset: assetCode };
}

// ─── Path Payment (Swap) ──────────────────────────────────────────────────────

export async function swapAssets(
  fromUserId,
  fromAssetCode,
  toAssetCode,
  amount,
) {
  const sender = await prisma.user.findUnique({ where: { id: fromUserId } });
  if (!sender?.stellarPublicKey || !sender?.stellarSecretKey)
    throw new Error("Stellar wallet not found");

  const keypair = StellarSdk.Keypair.fromSecret(
    decrypt(sender.stellarSecretKey),
  );
  const account = await server.loadAccount(sender.stellarPublicKey);

  // Log account state for debugging
  const xlmBalance = parseFloat(
    account.balances.find((b) => !b.asset_type || b.asset_type === "native")
      ?.balance || "0",
  );
  const numTrustlines = account.balances.filter(
    (b) => b.asset_type === "credit",
  ).length;
  console.log(
    `📋 Account state: Sequence=${account.sequenceNumber()}, XLM=${xlmBalance}, Trustlines=${numTrustlines}`,
  );
  console.log(
    `   Balances: ${account.balances.map((b) => `${b.balance} ${b.asset_code || "XLM"}`).join(" | ")}`,
  );

  const sendAsset =
    fromAssetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[fromAssetCode];
  const destAsset =
    toAssetCode === "XLM" ? StellarSdk.Asset.native() : ASSETS[toAssetCode];

  console.log(
    `🔄 SWAP: Finding path ${fromAssetCode} (${amount}) -> ${toAssetCode}`,
  );

  // 1. Get Path for destMin
  const paths = await server
    .strictSendPaths(sendAsset, amount.toString(), [destAsset])
    .call();
  if (!paths.records.length) {
    console.error(
      `❌ No liquidity path found: ${fromAssetCode} -> ${toAssetCode} for ${amount}`,
    );
    throw new Error("No liquidity found for swap.");
  }

  const bestPath = paths.records[0];
  const destMin = (parseFloat(bestPath.destination_amount) * 0.98).toFixed(7);

  // Extract the path assets (intermediate hops)
  const path = (bestPath.path || []).map((asset) => {
    if (asset.asset_type === "native") {
      return StellarSdk.Asset.native();
    }
    return new StellarSdk.Asset(asset.asset_code, asset.asset_issuer);
  });

  console.log(
    `✅ Path found: ${path.length} hops, Will receive ~${bestPath.destination_amount} ${toAssetCode}`,
  );
  if (path.length > 0) {
    console.log(
      `   Intermediate assets: ${path.map((a) => a.code || "XLM").join(" → ")}`,
    );
  }

  // 2. Build & Submit
  const numOperations = 1;
  const totalFeeInStroops = numOperations * parseInt(StellarSdk.BASE_FEE);
  const txFeeInXLM = totalFeeInStroops / 10000000; // Convert stroops to XLM

  // Reserve calculation:
  // - 0.5 XLM base reserve per entry (base account + each trustline)
  // - So: 0.5 * (1 + numExistingTrustlines + numNewTrustlinesInPath)
  // - Plus fee
  // - Plus safety buffer
  const newTrustlinesNeeded = path.filter((p) => {
    const code = p.code || "XLM";
    return !account.balances.some((b) => (b.asset_code || "XLM") === code);
  }).length;

  const totalReserveNeeded = 0.5 * (1 + numTrustlines + newTrustlinesNeeded);
  const minXLMRequired = totalReserveNeeded + txFeeInXLM + 0.1; // Add buffer

  console.log(
    `💰 Fee: ${txFeeInXLM} XLM, Trustlines: ${numTrustlines} existing + ${newTrustlinesNeeded} new`,
  );
  console.log(
    `🔐 Reserve needed: 0.5 × (1 + ${numTrustlines} + ${newTrustlinesNeeded}) = ${totalReserveNeeded.toFixed(8)} XLM`,
  );
  console.log(
    `   Min total needed: ${minXLMRequired.toFixed(8)} XLM, Have: ${xlmBalance.toFixed(8)} XLM`,
  );

  if (xlmBalance < minXLMRequired) {
    throw new Error(
      `Insufficient XLM for swap with this path. Need: ${minXLMRequired.toFixed(8)} XLM (${newTrustlinesNeeded} new trustlines × 0.5 + fee), Have: ${xlmBalance.toFixed(8)} XLM. Try swapping a smaller amount or get more XLM.`,
    );
  }

  const tx = new StellarSdk.TransactionBuilder(account, {
    fee: String(totalFeeInStroops),
    networkPassphrase,
  })
    .addOperation(
      StellarSdk.Operation.pathPaymentStrictSend({
        sendAsset,
        sendAmount: parseFloat(amount).toFixed(7),
        destination: sender.stellarPublicKey,
        destAsset,
        destMin,
        path, // Use the actual path from strictSendPaths
      }),
    )
    .setTimeout(30)
    .build();

  tx.sign(keypair);

  let result;
  try {
    result = await server.submitTransaction(tx);
  } catch (horizonErr) {
    // Stellar rejected the transaction - log detailed error
    const horizonResponse = horizonErr.response?.data;
    console.error(
      `❌ STELLAR REJECTED: ${horizonResponse?.title || "Unknown Error"}`,
    );
    console.error(
      "Stellar extras:",
      JSON.stringify(horizonResponse?.extras || {}, null, 2),
    );

    // Re-throw with more context
    if (horizonResponse?.extras?.result_codes) {
      const codes = horizonResponse.extras.result_codes;
      const txCode = codes.transaction;
      const opCodes = codes.operations || [];
      throw new Error(
        `Stellar rejected: tx_code=${txCode}, op_codes=[${opCodes.join(", ")}]`,
      );
    }
    throw horizonErr;
  }

  // ✅ THE FIX: Decode XDR to get EXACT amount received
  const resultXDR = StellarSdk.xdr.TransactionResult.fromXDR(
    result.result_xdr,
    "base64",
  );
  const actualReceivedRaw = resultXDR
    .result()
    .results()[0]
    .tr()
    .pathPaymentStrictSendResult()
    .success()
    .last()
    .amount()
    .toString();
  // Convert stroops to XLM/USDC (1 unit = 10^7 stroops)
  const actualReceived = parseFloat(actualReceivedRaw) / 10000000;

  console.log(
    `✅ Swap submitted: Hash ${result.hash} | Received: ${actualReceived} ${toAssetCode}`,
  );

  // 3. Record BOTH LEGS of the swap in DB with shared swapId
  const swapId = `swap_${result.hash}_${Date.now()}`;

  // Outgoing leg (e.g., send USDC)
  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: "swap",
      status: "confirmed",
      amount: parseFloat(amount),
      asset: fromAssetCode,
      network: "stellar",
      fromAddress: sender.stellarPublicKey,
      toAddress: sender.stellarPublicKey,
      stellarTxHash: result.hash,
      isSwap: true,
      swapId,
      swapFromAsset: fromAssetCode,
      swapToAsset: toAssetCode,
      receivedAmount: actualReceived,
    },
  });

  // Incoming leg (e.g., receive XLM)
  await prisma.transaction.create({
    data: {
      userId: fromUserId,
      type: "swap",
      status: "confirmed",
      amount: actualReceived,
      asset: toAssetCode,
      network: "stellar",
      fromAddress: sender.stellarPublicKey,
      toAddress: sender.stellarPublicKey,
      stellarTxHash: `${result.hash}_receive`,
      isSwap: true,
      swapId,
      swapFromAsset: fromAssetCode,
      swapToAsset: toAssetCode,
      receivedAmount: actualReceived,
    },
  });

  // Send swap confirmation email
  try {
    await sendSwapCompleteEmail(
      sender.email,
      fromAssetCode,
      toAssetCode,
      parseFloat(amount),
      actualReceived.toFixed(6),
    );
  } catch (err) {
    console.warn("⚠️  Swap email failed:", err.message);
  }

  return {
    hash: result.hash,
    fromAsset: fromAssetCode,
    toAsset: toAssetCode,
    sentAmount: parseFloat(amount),
    receivedAmount: actualReceived,
  };
}

// ─── Resolve username ─────────────────────────────────────────────────────────

export async function resolveUsername(username) {
  const lower = username
    .replace("@dayfi.me", "")
    .replace("@", "")
    .toLowerCase();
  const user = await prisma.user.findUnique({
    where: { username: lower },
    select: { username: true, stellarPublicKey: true },
  });
  if (!user?.stellarPublicKey) return null;
  return {
    username: `${user.username}@dayfi.me`,
    address: user.stellarPublicKey,
    network: "stellar",
  };
}

// ─── Transaction history ──────────────────────────────────────────────────────

export async function getStellarTransactions(publicKey, limit = 20) {
  try {
    const page = await server
      .transactions()
      .forAccount(publicKey)
      .limit(limit)
      .order("desc")
      .call();
    return page.records.map((tx) => ({
      hash: tx.hash,
      createdAt: tx.created_at,
      memo: tx.memo,
      successful: tx.successful,
    }));
  } catch {
    return [];
  }
}

// ─── Auto-fund new user wallets from master wallet ─────────────────────────

export async function fundNewUserWallet(userPublicKey, userId = null) {
  const masterPublicKey = process.env.MASTER_WALLET_PUBLIC_KEY;
  const masterSecretEncrypted = process.env.MASTER_WALLET_SECRET_KEY;
  const fundingAmount = process.env.FUNDING_AMOUNT || "5";

  if (!masterPublicKey || !masterSecretEncrypted) {
    console.warn("⚠️  Master wallet not configured. Skipping auto-funding.");
    return null;
  }

  try {
    // Decrypt the master wallet secret key
    const masterSecret = decrypt(masterSecretEncrypted);
    const masterKeypair = StellarSdk.Keypair.fromSecret(masterSecret);

    // Get master account
    const masterAccount = await server.loadAccount(masterPublicKey);

    // Check if destination account exists
    let destExists = true;
    try {
      await server.loadAccount(userPublicKey);
    } catch {
      destExists = false;
    }

    const txBuilder = new StellarSdk.TransactionBuilder(masterAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase,
    });

    if (!destExists) {
      // Create account with initial balance
      txBuilder.addOperation(
        StellarSdk.Operation.createAccount({
          destination: userPublicKey,
          startingBalance: fundingAmount,
        }),
      );
    } else {
      // Account exists, just send XLM
      txBuilder.addOperation(
        StellarSdk.Operation.payment({
          destination: userPublicKey,
          asset: StellarSdk.Asset.native(),
          amount: fundingAmount,
        }),
      );
    }

    const tx = txBuilder.setTimeout(30).build();
    tx.sign(masterKeypair);
    const result = await server.submitTransaction(tx);

    console.log(`✅ Funded ${userPublicKey} with ${fundingAmount} XLM`);

    // Record transaction if userId is provided
    if (userId) {
      await prisma.transaction.create({
        data: {
          userId,
          type: "receive",
          status: "confirmed",
          amount: parseFloat(fundingAmount),
          asset: "XLM",
          network: "stellar",
          fromAddress: masterPublicKey,
          toAddress: userPublicKey,
          stellarTxHash: result.hash,
          memo: "Initial account funding",
        },
      });
      console.log(`📝 Recorded funding transaction for user ${userId}`);
    }

    return result;
  } catch (err) {
    console.error("❌ Auto-funding failed:", err.message);
    // Don't throw — allow user creation to succeed even if funding fails
    return null;
  }
}

// ─── Send from Master Wallet (Admin) ──────────────────────────────────────────

export async function sendFromMasterWallet(
  recipientAddress,
  amount,
  memo = "",
) {
  const masterPublicKey = process.env.MASTER_WALLET_PUBLIC_KEY;
  const masterSecretEncrypted = process.env.MASTER_WALLET_SECRET_KEY;

  if (!masterPublicKey || !masterSecretEncrypted) {
    throw new Error("Master wallet not configured");
  }

  // Validate amount
  const amountNum = parseFloat(amount);
  if (isNaN(amountNum) || amountNum <= 0) {
    throw new Error("Invalid amount");
  }

  // Validate recipient address
  if (
    !recipientAddress ||
    recipientAddress.length !== 56 ||
    !recipientAddress.startsWith("G")
  ) {
    throw new Error("Invalid recipient address");
  }

  try {
    // Decrypt the master wallet secret key
    const masterSecret = decrypt(masterSecretEncrypted);
    const masterKeypair = StellarSdk.Keypair.fromSecret(masterSecret);

    // Get master account
    const masterAccount = await server.loadAccount(masterPublicKey);

    // Verify recipient exists
    try {
      await server.loadAccount(recipientAddress);
    } catch {
      throw new Error("Recipient account does not exist on network");
    }

    const txBuilder = new StellarSdk.TransactionBuilder(masterAccount, {
      fee: StellarSdk.BASE_FEE,
      networkPassphrase,
    });

    txBuilder.addOperation(
      StellarSdk.Operation.payment({
        destination: recipientAddress,
        asset: StellarSdk.Asset.native(),
        amount: amountNum.toString(),
      }),
    );

    if (memo) {
      txBuilder.addMemo(StellarSdk.Memo.text(memo));
    }

    const tx = txBuilder.setTimeout(30).build();
    tx.sign(masterKeypair);
    const result = await server.submitTransaction(tx);

    console.log(`✅ Sent ${amountNum} XLM from master to ${recipientAddress}`);
    return {
      success: true,
      hash: result.hash,
      amount: amountNum,
      recipient: recipientAddress,
      memo: memo || null,
    };
  } catch (err) {
    console.error("❌ Master send failed:", err.message);
    throw err;
  }
}

// ─── Sync blockchain transactions (optional, for external transfers) ──────────

export async function syncBlockchainTransactions(userId) {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user?.stellarPublicKey) throw new Error("User has no Stellar wallet");

  try {
    // Get recent transactions from Stellar
    const page = await server
      .transactions()
      .forAccount(user.stellarPublicKey)
      .limit(50)
      .order("desc")
      .call();

    let synced = 0;

    for (const tx of page.records) {
      // Skip if already in database
      const existing = await prisma.transaction.findUnique({
        where: { stellarTxHash: tx.hash },
      });
      if (existing) continue;

      // Process operations in the transaction
      const ops = tx.operations();
      for (const op of ops) {
        if (
          op.type_code === "payment" ||
          op.type_code === "path_payment_strict_send"
        ) {
          // Only record transactions TO this user
          if (
            op.to === user.stellarPublicKey ||
            op.destination === user.stellarPublicKey
          ) {
            const amount = parseFloat(op.amount || op.send_amount || 0);
            if (amount > 0) {
              // Determine asset
              let asset = "XLM";
              if (
                op.asset_type === "credit_alphanum4" ||
                op.asset_type === "credit_alphanum12"
              ) {
                asset = op.asset_code || "UNKNOWN";
              }

              // For path payments, extract the received amount
              let receivedAmount = amount;
              if (op.type_code === "path_payment_strict_send") {
                // Could be a swap - try to get more details
                const opDetails = await server.operationDetail(op.id).call();
                if (opDetails && opDetails.body_details) {
                  // This is a swap
                  await prisma.transaction.create({
                    data: {
                      userId,
                      type: "swap",
                      status: "confirmed",
                      amount: parseFloat(op.send_amount || 0),
                      asset: op.send_asset_code || "XLM",
                      network: "stellar",
                      fromAddress: op.from,
                      toAddress: user.stellarPublicKey,
                      stellarTxHash: tx.hash,
                      isSwap: true,
                      swapFromAsset: op.send_asset_code || "XLM",
                      swapToAsset: op.asset_code || "XLM",
                      receivedAmount: parseFloat(op.amount || 0),
                    },
                  });
                  synced++;
                  continue;
                }
              }

              // Regular receive transaction
              await prisma.transaction.create({
                data: {
                  userId,
                  type: "receive",
                  status: "confirmed",
                  amount,
                  asset,
                  network: "stellar",
                  fromAddress: op.from,
                  toAddress: user.stellarPublicKey,
                  stellarTxHash: tx.hash,
                  memo: tx.memo || null,
                },
              });
              synced++;
            }
          }
        }
      }
    }

    console.log(`✅ Synced ${synced} transactions for user ${userId}`);
    return { synced };
  } catch (err) {
    console.error("❌ Sync failed:", err.message);
    throw err;
  }
}

export { server, networkPassphrase };
