export type PlAlertKind = 'profit' | 'loss';

export interface PlAlertEmail {
	subject: string;
	text: string;
	html: string;
}

function escapeHtml(value: string): string {
	return value
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

function formatUsd(value: number): string {
	const abs = Math.abs(value).toLocaleString('en-US', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2
	});
	if (value > 0) return `+${abs}`;
	if (value < 0) return `-${abs}`;
	return abs;
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

export function buildPlAlertEmail(
	kind: PlAlertKind,
	adjusted: number,
	threshold: number,
	at: Date = new Date()
): PlAlertEmail {
	const isProfit = kind === 'profit';
	const accent = isProfit ? '#3dff6a' : '#ff4d4d';
	const muted = isProfit ? '#8fd9a4' : '#f0a0a0';
	const label = isProfit ? 'Profit' : 'Loss';
	const icon = isProfit ? '🟢' : '🔴';
	const amount = formatUsd(adjusted);
	const limit = formatUsd(isProfit ? threshold : -threshold);
	const when = formatWhen(at);
	const headline = isProfit
		? 'Adjusted P/L crossed the profit threshold.'
		: 'Adjusted P/L crossed the loss threshold.';

	const subject = `${icon} ${label} ${amount}`;
	const text = [
		`${label} alert`,
		headline,
		`Adjusted P/L: ${amount}`,
		`Threshold: ${limit}`,
		`When: ${when} (Asia/Bangkok)`
	].join('\n');

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
${escapeHtml(headline)} ${escapeHtml(amount)} / ${escapeHtml(limit)}
</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#0a0a0a" style="background:#0a0a0a;margin:0;padding:0;">
  <tr>
    <td align="center" style="padding:36px 16px;">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;">
        <tr>
          <td>
            <table role="presentation" cellpadding="0" cellspacing="0">
              <tr>
                <td width="12" height="12" bgcolor="${accent}" style="width:12px;height:12px;background:${accent};border-radius:12px;font-size:0;line-height:12px;">&nbsp;</td>
                <td style="padding-left:10px;color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;font-weight:600;letter-spacing:0.12em;text-transform:uppercase;">${escapeHtml(label)}</td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:18px;color:${accent};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:44px;font-weight:800;letter-spacing:-0.04em;line-height:1;">${escapeHtml(amount)}</td>
        </tr>
        <tr>
          <td style="padding-top:12px;color:${muted};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.5;">${escapeHtml(headline)}</td>
        </tr>
        <tr>
          <td style="padding-top:28px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid #2a2a2a;">
              <tr>
                <td width="50%" valign="top" style="padding-top:18px;color:${muted};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;letter-spacing:0.04em;text-transform:uppercase;">
                  Threshold<br>
                  <span style="display:inline-block;padding-top:6px;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:16px;font-weight:600;letter-spacing:0;text-transform:none;">${escapeHtml(limit)}</span>
                </td>
                <td width="50%" valign="top" align="right" style="padding-top:18px;color:${muted};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;letter-spacing:0.04em;text-transform:uppercase;">
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
