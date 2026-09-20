import type { PlAlertEmail } from '$lib/pl-alert-email.js';

export interface EquityWarningAccountLine {
	accountNumber: string;
	accountName: string;
	brokerName: string;
	equity: number;
	threshold: number;
}

function escapeHtml(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

function formatUsd(value: number): string {
	return value.toLocaleString('en-US', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2
	});
}

function formatWhen(at: Date): string {
	return at.toLocaleString('en-GB', {
		timeZone: 'Asia/Bangkok',
		day: '2-digit',
		month: 'short',
		year: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
		hour12: false
	});
}

export function buildEquityWarningEmail(input: {
	unit: number;
	unitName: string;
	warnPct: number;
	accounts: EquityWarningAccountLine[];
	at?: Date;
}): PlAlertEmail {
	const when = formatWhen(input.at ?? new Date());
	const unitLabel = input.unitName || `Unit ${input.unit}`;
	const headline = `${unitLabel} has at least one account below the warning equity threshold.`;
	const subject = `Low equity ${unitLabel}`;
	const accountLines = input.accounts.map((account) => {
		const name = account.accountName || account.accountNumber;
		return `${name} (${account.accountNumber}) ${account.brokerName}: ${formatUsd(account.equity)} / ${formatUsd(account.threshold)}`;
	});
	const text = [
		'Low equity alert',
		headline,
		`Unit: ${unitLabel} (#${input.unit})`,
		`Warn %: ${input.warnPct}`,
		...accountLines,
		`When: ${when} (Asia/Bangkok)`
	].join('\n');

	const rows = input.accounts
		.map((account) => {
			const name = escapeHtml(account.accountName || account.accountNumber);
			return `<tr>
                <td style="padding:10px 0;color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;">
                  ${name}<br>
                  <span style="color:#f0a0a0;font-size:12px;">${escapeHtml(account.accountNumber)} · ${escapeHtml(account.brokerName)}</span>
                </td>
                <td align="right" style="padding:10px 0;color:#ff4d4d;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:16px;font-weight:600;">
                  ${escapeHtml(formatUsd(account.equity))}<br>
                  <span style="color:#f0a0a0;font-size:12px;font-weight:500;">/ ${escapeHtml(formatUsd(account.threshold))}</span>
                </td>
              </tr>`;
		})
		.join('');

	const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<meta name="supported-color-schemes" content="dark">
<title>${escapeHtml(subject)}</title>
</head>
<body style="margin:0;padding:0;background:#0a0a0a;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
${escapeHtml(headline)}
</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#0a0a0a" style="background:#0a0a0a;margin:0;padding:0;">
  <tr>
    <td align="center" style="padding:36px 16px;">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;">
        <tr>
          <td>
            <table role="presentation" cellpadding="0" cellspacing="0">
              <tr>
                <td width="12" height="12" bgcolor="#ff4d4d" style="width:12px;height:12px;background:#ff4d4d;border-radius:12px;font-size:0;line-height:12px;">&nbsp;</td>
                <td style="padding-left:10px;color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;letter-spacing:0.12em;text-transform:uppercase;">Low equity</td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:18px;color:#ff4d4d;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:32px;font-weight:800;letter-spacing:-0.04em;line-height:1.1;">${escapeHtml(unitLabel)}</td>
        </tr>
        <tr>
          <td style="padding-top:12px;color:#f0a0a0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.5;">${escapeHtml(headline)}</td>
        </tr>
        <tr>
          <td style="padding-top:28px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #2a2a2a;">
              ${rows}
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:18px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #2a2a2a;">
              <tr>
                <td width="50%" valign="top" style="padding-top:18px;color:#f0a0a0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;letter-spacing:0.04em;text-transform:uppercase;">
                  Warn %<br>
                  <span style="display:inline-block;padding-top:6px;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:16px;font-weight:600;letter-spacing:0;text-transform:none;">${input.warnPct}%</span>
                </td>
                <td width="50%" valign="top" align="right" style="padding-top:18px;color:#f0a0a0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;letter-spacing:0.04em;text-transform:uppercase;">
                  When<br>
                  <span style="display:inline-block;padding-top:6px;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:16px;font-weight:600;letter-spacing:0;text-transform:none;">${escapeHtml(when)}</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:32px;color:#7a7a7a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">Profit Monitor</td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;

	return { subject, text, html };
}
