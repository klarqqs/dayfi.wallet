// src/services/emailService.js
import { Resend } from 'resend';
import dotenv from 'dotenv';
dotenv.config();

const resend = new Resend(process.env.RESEND_API_KEY);

const FROM = process.env.FROM_EMAIL
  ? `${process.env.FROM_NAME || 'DayFi'} <${process.env.FROM_EMAIL}>`
  : 'DayFi <onboarding@resend.dev>';

const LOGO_URL = 'https://drive.google.com/uc?export=view&id=1hD4L1_4HIJGCDkV7p72lV69es1DLlrQX';

// ─── Shared Styles ─────────────────────────────────────────────────────────────

const fontImport = `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');`;

const baseStyles = `
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #090909;
    padding: 40px 0;
  }
`;

// Matches AppBackground dark radial gradient
const wrapperStyle = `
  background: radial-gradient(ellipse at 20% 10%, #252525 0%, #151515 50%, #090909 100%);
  border-radius: 20px;
  overflow: hidden;
  max-width: 480px;
  margin: 0 auto;
  border: 1px solid #1E1E1E;
`;

function shell(content) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>${fontImport}${baseStyles}</style>
</head>
<body style="background:#090909;padding:40px 16px;">
  <table width="100%" cellpadding="0" cellspacing="0">
    <tr>
      <td align="center">
        <table cellpadding="0" cellspacing="0" style="${wrapperStyle}">
          <!-- Logo -->
          <tr>
            <td style="padding:36px 40px 0;text-align:center;">
              <img src="${LOGO_URL}" alt="DayFi" height="36" style="display:inline-block;" />
            </td>
          </tr>
          ${content}
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px 32px;border-top:1px solid #1E1E1E;text-align:center;">
              <p style="color:#444;font-size:11px;font-family:'Inter',sans-serif;line-height:1.6;">
                If you didn't request this, please ignore this email.<br>
                © ${new Date().getFullYear()} DayFi — Send money with just a username.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function card(inner, borderColor = '#1E1E1E') {
  return `<div style="background:#111111;border:1px solid ${borderColor};border-radius:14px;padding:24px;margin-bottom:16px;text-align:center;">${inner}</div>`;
}

// ─── OTP Email ─────────────────────────────────────────────────────────────────

export async function sendOTP(email, otp, isNewUser = false) {
  const subject = isNewUser
    ? `${otp} is your DayFi verification code`
    : `${otp} — Sign in to DayFi`;

  const content = `
    <tr>
      <td style="padding:28px 32px 8px;text-align:center;">
        <p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;letter-spacing:0.5px;margin-bottom:6px;">
          ${isNewUser ? 'Create your wallet' : 'Sign in to your wallet'}
        </p>
        <h2 style="color:#ffffff;font-size:22px;font-weight:600;font-family:'Inter',sans-serif;letter-spacing:-0.5px;margin-bottom:28px;">
          ${isNewUser ? 'Welcome to DayFi' : 'Your sign-in code'}
        </h2>
        ${card(`
          <p style="color:#888888;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:14px;">Verification Code</p>
          <p style="color:#ffffff;font-size:44px;font-weight:700;font-family:'Inter',sans-serif;letter-spacing:14px;margin-bottom:10px;">${otp}</p>
          <p style="color:#444444;font-size:12px;font-family:'Inter',sans-serif;">Expires in 10 minutes</p>
        `)}
        <p style="color:#666666;font-size:13px;font-family:'Inter',sans-serif;line-height:1.7;margin-top:8px;">
          ${isNewUser
            ? 'Enter this code in the DayFi app to create your USDC wallet.'
            : 'Enter this code to access your DayFi. Never share this code with anyone.'}
        </p>
      </td>
    </tr>`;

  const html = shell(content);

  const { error } = await resend.emails.send({ from: FROM, to: email, subject, html,
    text: `Your DayFi verification code is: ${otp}\n\nExpires in 10 minutes. Never share this code.` });

  if (error) throw new Error(error.message);
  console.log(`📧 OTP sent to ${email}`);
}

// ─── Welcome Email ─────────────────────────────────────────────────────────────

export async function sendWelcomeEmail(email, username) {
  const content = `
    <tr>
      <td style="padding:28px 32px 8px;text-align:center;">
        <p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;margin-bottom:6px;">Your wallet is ready</p>
        <h2 style="color:#ffffff;font-size:22px;font-weight:600;font-family:'Inter',sans-serif;letter-spacing:-0.5px;margin-bottom:28px;">
          Welcome aboard 🎉
        </h2>
        ${card(`
          <p style="color:#888888;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px;">Your DayFi Username</p>
          <p style="color:#ffffff;font-size:26px;font-weight:700;font-family:'Inter',sans-serif;margin-bottom:4px;">@${username}</p>
          <p style="color:#444444;font-size:13px;font-family:'Inter',sans-serif;">${username}@dayfi.me</p>
        `)}
        <p style="color:#666666;font-size:13px;font-family:'Inter',sans-serif;line-height:1.7;margin-top:8px;">
          Anyone can now send you USDC using just your username.<br>Your funds are secured on the Stellar network.
        </p>
      </td>
    </tr>`;

  const html = shell(content);

  const { error } = await resend.emails.send({ from: FROM, to: email,
    subject: `welcome to dayFi, @${username}!`, html });

  if (error) throw new Error(error.message);
  console.log(`📧 Welcome email sent to ${email}`);
}

// ─── Payment Received ──────────────────────────────────────────────────────────

export async function sendPaymentReceivedEmail(email, senderUsername, amount, asset, memo = null) {
  const content = `
    <tr>
      <td style="padding:28px 32px 8px;text-align:center;">
        <p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;margin-bottom:6px;">You received a payment</p>
        <h2 style="color:#ffffff;font-size:22px;font-weight:600;font-family:'Inter',sans-serif;letter-spacing:-0.5px;margin-bottom:28px;">
          Money's in ✅
        </h2>
        ${card(`
          <p style="color:#888888;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px;">From</p>
          <p style="color:#ffffff;font-size:20px;font-weight:700;font-family:'Inter',sans-serif;">@${senderUsername}</p>
        `)}
        ${card(`
          <p style="color:#00E676;font-size:12px;font-family:'Inter',sans-serif;margin-bottom:10px;">Amount Received</p>
          <p style="color:#ffffff;font-size:34px;font-weight:700;font-family:'Inter',sans-serif;letter-spacing:-1px;">+${amount} ${asset}</p>
        `, '#1A3326')}
        ${memo ? card(`<p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;">📝 ${memo}</p>`) : ''}
        <p style="color:#666666;font-size:13px;font-family:'Inter',sans-serif;line-height:1.7;margin-top:8px;">
          Your payment is confirmed and available in your DayFi.
        </p>
      </td>
    </tr>`;

  const html = shell(content);

  const { error } = await resend.emails.send({ from: FROM, to: email,
    subject: `You received ${amount} ${asset} from @${senderUsername}`, html });

  if (error) throw new Error(error.message);
  console.log(`📧 Payment received email sent to ${email}`);
}

// ─── Payment Sent ──────────────────────────────────────────────────────────────

export async function sendPaymentSentEmail(email, recipientUsername, amount, asset, memo = null) {
  const content = `
    <tr>
      <td style="padding:28px 32px 8px;text-align:center;">
        <p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;margin-bottom:6px;">Payment sent</p>
        <h2 style="color:#ffffff;font-size:22px;font-weight:600;font-family:'Inter',sans-serif;letter-spacing:-0.5px;margin-bottom:28px;">
          Sent successfully ✓
        </h2>
        ${card(`
          <p style="color:#888888;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px;">To</p>
          <p style="color:#ffffff;font-size:20px;font-weight:700;font-family:'Inter',sans-serif;">@${recipientUsername}</p>
        `)}
        ${card(`
          <p style="color:#FF4444;font-size:12px;font-family:'Inter',sans-serif;margin-bottom:10px;">Amount Sent</p>
          <p style="color:#ffffff;font-size:34px;font-weight:700;font-family:'Inter',sans-serif;letter-spacing:-1px;">−${amount} ${asset}</p>
        `, '#3D1515')}
        ${memo ? card(`<p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;">📝 ${memo}</p>`) : ''}
        <p style="color:#666666;font-size:13px;font-family:'Inter',sans-serif;line-height:1.7;margin-top:8px;">
          Your payment has been confirmed on the Stellar network.
        </p>
      </td>
    </tr>`;

  const html = shell(content);

  const { error } = await resend.emails.send({ from: FROM, to: email,
    subject: `Payment sent to @${recipientUsername}`, html });

  if (error) throw new Error(error.message);
  console.log(`📧 Payment sent email sent to ${email}`);
}

// ─── Swap Complete ─────────────────────────────────────────────────────────────

export async function sendSwapCompleteEmail(email, fromAsset, toAsset, sentAmount, receivedAmount) {
  const content = `
    <tr>
      <td style="padding:28px 32px 8px;text-align:center;">
        <p style="color:#888888;font-size:13px;font-family:'Inter',sans-serif;margin-bottom:6px;">Swap completed</p>
        <h2 style="color:#ffffff;font-size:22px;font-weight:600;font-family:'Inter',sans-serif;letter-spacing:-0.5px;margin-bottom:28px;">
          Exchange confirmed ⇄
        </h2>
        ${card(`
          <p style="color:#888888;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px;">You Swapped</p>
          <p style="color:#FF4444;font-size:24px;font-weight:700;font-family:'Inter',sans-serif;">−${sentAmount} ${fromAsset}</p>
        `, '#3D1515')}
        <p style="color:#444444;font-size:18px;font-family:'Inter',sans-serif;margin:4px 0 12px;">↓</p>
        ${card(`
          <p style="color:#00E676;font-size:11px;font-family:'Inter',sans-serif;letter-spacing:2px;text-transform:uppercase;margin-bottom:10px;">You Received</p>
          <p style="color:#ffffff;font-size:24px;font-weight:700;font-family:'Inter',sans-serif;">+${receivedAmount} ${toAsset}</p>
        `, '#1A3326')}
        <p style="color:#666666;font-size:13px;font-family:'Inter',sans-serif;line-height:1.7;margin-top:8px;">
          Your swap on the Stellar DEX has been confirmed.
        </p>
      </td>
    </tr>`;

  const html = shell(content);

  const { error } = await resend.emails.send({ from: FROM, to: email,
    subject: `Swap complete: ${sentAmount} ${fromAsset} → ${receivedAmount} ${toAsset}`, html });

  if (error) throw new Error(error.message);
  console.log(`📧 Swap complete email sent to ${email}`);
}