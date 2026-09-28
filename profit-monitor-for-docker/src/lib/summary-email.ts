export interface SummaryEmailAccount {
	accountNumber: string;
	accountName: string;
	brokerName: string;
	balance: number;
	equity: number;
}

export interface SummaryEmailUnit {
	unit: number;
	name: string;
	capital: number;
	totalBalance: number;
	profitLoss: number;
	wd: number;
	dp: number;
	pending: number;
	accounts: SummaryEmailAccount[];
}

export interface SummaryBrokerAccount {
	number: string;
	equity: number;
}

export interface SummaryBrokerName {
	name: string;
	equity: number;
	accounts: SummaryBrokerAccount[];
}

export interface SummaryBroker {
	broker: string;
	equity: number;
	names: SummaryBrokerName[];
}

export interface SummaryPending {
	withdrawnAt: string;
	unit: number;
	accountNumber: string;
	accountName: string;
	brokerName: string;
	amount: number;
	note: string;
}

export interface SummaryWallet {
	name: string;
	balance: number;
	updatedAt: string;
}

export interface SummaryEmailData {
	at: Date;
	adjusted: number;
	initialCapital: number;
	bookTotal: number;
	sumWd: number;
	sumDp: number;
	snapshot: { baseline: number; delta: number } | null;
	units: SummaryEmailUnit[];
	brokers: SummaryBroker[];
	pending: SummaryPending[];
	wallet: SummaryWallet;
}

export interface SummaryEmail {
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
	if (Math.abs(value) < 0.005) return abs;
	return value > 0 ? `+${abs}` : `-${abs}`;
}

function formatPlain(value: number): string {
	return Math.abs(value).toLocaleString('en-US', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2
	});
}

function formatPercent(value: number): string {
	const shown = Math.abs(value).toLocaleString('en-US', {
		minimumFractionDigits: 2,
		maximumFractionDigits: 2
	});
	if (Math.abs(value) < 0.005) return `${shown}%`;
	return value > 0 ? `+${shown}%` : `-${shown}%`;
}

function tone(value: number): string {
	if (Math.abs(value) < 0.005) return '#ececec';
	return value > 0 ? '#3dff6a' : '#ff4d4d';
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

function formatStamp(iso: string): string {
	const date = new Date(iso);
	if (Number.isNaN(date.getTime())) return '';
	const parts = new Intl.DateTimeFormat('en-GB', {
		timeZone: 'Asia/Bangkok',
		day: '2-digit',
		month: '2-digit',
		year: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
		second: '2-digit',
		hour12: false
	}).formatToParts(date);
	const pick = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value || '';
	return `${pick('day')}/${pick('month')}/${pick('year')} ${pick('hour')}:${pick('minute')}:${pick('second')}`;
}

function percentOf(amount: number, base: number): number | null {
	if (!(base > 0)) return null;
	return (amount / base) * 100;
}

export function buildSummaryEmail(data: SummaryEmailData): SummaryEmail {
	const when = formatWhen(data.at);
	const adjustedPct = percentOf(data.adjusted, data.initialCapital);
	const heroValue = data.snapshot ? data.snapshot.delta : data.adjusted;
	const heroLabel = data.snapshot ? 'Snapshot' : 'P/L';
	const subject = data.snapshot
		? `Snapshot ${formatUsd(data.snapshot.delta)} · P/L ${formatUsd(data.adjusted)}`
		: `P/L ${formatUsd(data.adjusted)}`;

	const textLines = [
		'Profit Monitor summary',
		`${when} (Asia/Bangkok)`,
		'Amounts in USD',
		'',
		`${heroLabel}: ${formatUsd(heroValue)}`
	];
	if (data.snapshot) {
		textLines.push(`Live P/L: ${formatUsd(data.adjusted)}${adjustedPct === null ? '' : ` (${formatPercent(adjustedPct)})`}`);
		textLines.push(`Snapshot baseline: ${formatUsd(data.snapshot.baseline)}`);
	} else if (adjustedPct !== null) {
		textLines.push(`Percent: ${formatPercent(adjustedPct)}`);
	}
	textLines.push(`SUM WD: ${formatUsd(data.sumWd)}`);
	textLines.push(`SUM DP: ${formatPlain(data.sumDp) === '0.00' ? formatPlain(data.sumDp) : `-${formatPlain(data.sumDp)}`}`);
	textLines.push('');
	for (const unit of data.units) {
		const unitPct = percentOf(unit.profitLoss, unit.capital);
		textLines.push(`${unit.name} #${unit.unit}`);
		textLines.push(`P/L: ${formatUsd(unit.profitLoss)}${unitPct === null ? '' : ` (${formatPercent(unitPct)})`}`);
		textLines.push(`Capital: ${formatPlain(unit.capital)}`);
		textLines.push(`Total: ${formatPlain(unit.totalBalance)}`);
		if (unit.wd > 0) textLines.push(`WD: ${formatUsd(unit.wd)}`);
		if (unit.dp > 0) textLines.push(`DP: -${formatPlain(unit.dp)}`);
		if (unit.pending > 0) textLines.push(`Pending WD: ${formatPlain(unit.pending)}`);
		for (const account of unit.accounts) {
			textLines.push(
				`${account.accountNumber} · ${account.accountName} · ${account.brokerName} · Balance ${formatPlain(account.balance)} · Equity ${formatPlain(account.equity)}`
			);
		}
		textLines.push('');
	}

	textLines.push('TOTAL');
	if (data.initialCapital > 0) textLines.push(`Capital: ${formatPlain(data.initialCapital)}`);
	textLines.push(formatPlain(data.bookTotal));
	for (const broker of data.brokers) {
		textLines.push(`${broker.broker} (${broker.names.length}) ${formatPlain(broker.equity)}`);
		for (const name of broker.names) {
			if (name.accounts.length === 1) {
				textLines.push(`  ${name.name} ${name.accounts[0].number} ${formatPlain(name.equity)}`);
			} else {
				textLines.push(`  ${name.name} (${name.accounts.length}) ${formatPlain(name.equity)}`);
				for (const account of name.accounts) {
					textLines.push(`    ${account.number} ${formatPlain(account.equity)}`);
				}
			}
		}
	}
	textLines.push('');
	textLines.push('Pending Withdrawals');
	if (data.pending.length === 0) {
		textLines.push('No pending withdrawals.');
	} else {
		const pendingTotal = data.pending.reduce((sum, item) => sum + item.amount, 0);
		textLines.push(`Total ${formatPlain(pendingTotal)}`);
		for (const item of data.pending) {
			textLines.push(
				`${formatStamp(item.withdrawnAt)} · Unit ${item.unit === 0 ? 'Unknown' : item.unit} · ${item.accountNumber} · ${item.accountName} · ${item.brokerName} · ${formatPlain(item.amount)}${item.note ? ` · ${item.note}` : ''}`
			);
		}
	}
	textLines.push('');
	textLines.push(data.wallet.name || 'Wallet');
	textLines.push(formatPlain(data.wallet.balance));
	if (data.wallet.updatedAt) textLines.push(`Updated ${formatStamp(data.wallet.updatedAt)}`);

	const fact = (label: string, value: string, color = '#f5f5f5') => `
		<td valign="top" style="padding:14px 12px 0 0;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;letter-spacing:0.06em;text-transform:uppercase;">
			${escapeHtml(label)}<br>
			<span style="display:inline-block;padding-top:4px;color:${color};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:15px;font-weight:650;letter-spacing:0;text-transform:none;">${escapeHtml(value)}</span>
		</td>`;

	const accountRows = (unit: SummaryEmailUnit) =>
		unit.accounts
			.map(
				(account) => `<tr>
					<td style="padding:8px 0;border-top:1px solid #242424;color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;">
						${escapeHtml(account.accountNumber)} · ${escapeHtml(account.accountName)}
						<div style="padding-top:2px;color:#9a9a9a;font-size:12px;">${escapeHtml(account.brokerName)}</div>
					</td>
					<td align="right" style="padding:8px 0 8px 12px;border-top:1px solid #242424;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;white-space:nowrap;">
						${escapeHtml(formatPlain(account.balance))}
						<div style="padding-top:2px;color:#9a9a9a;font-size:12px;">Eq ${escapeHtml(formatPlain(account.equity))}</div>
					</td>
				</tr>`
			)
			.join('');

	const unitBlocks = data.units
		.map((unit) => {
			const unitPct = percentOf(unit.profitLoss, unit.capital);
			const extras = [
				unit.wd > 0 ? `WD ${formatUsd(unit.wd)}` : '',
				unit.dp > 0 ? `DP -${formatPlain(unit.dp)}` : '',
				unit.pending > 0 ? `Pending ${formatPlain(unit.pending)}` : ''
			].filter(Boolean);
			return `<tr>
				<td style="padding-top:22px;">
					<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #2a2a2a;background:#111;">
						<tr>
							<td style="padding:16px 16px 0;">
								<div style="color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:700;">${escapeHtml(unit.name)} <span style="color:#9a9a9a;font-weight:500;">#${unit.unit}</span></div>
							</td>
							<td align="right" style="padding:16px 16px 0;color:${tone(unit.profitLoss)};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:18px;font-weight:750;">
								${escapeHtml(formatUsd(unit.profitLoss))}
								${unitPct === null ? '' : `<div style="padding-top:2px;font-size:12px;">${escapeHtml(formatPercent(unitPct))}</div>`}
							</td>
						</tr>
						<tr>
							<td colspan="2" style="padding:10px 16px 0;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;line-height:1.5;">
								Capital ${escapeHtml(formatPlain(unit.capital))} · Total ${escapeHtml(formatPlain(unit.totalBalance))}
								${extras.length ? `<br>${escapeHtml(extras.join(' · '))}` : ''}
							</td>
						</tr>
						<tr>
							<td colspan="2" style="padding:8px 16px 14px;">
								<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
									${accountRows(unit)}
								</table>
							</td>
						</tr>
					</table>
				</td>
			</tr>`;
		})
		.join('');

	const brokerRows = data.brokers
		.map((broker) => {
			const names = broker.names
				.map((name) => {
					const accounts =
						name.accounts.length > 1
							? name.accounts
									.map(
										(account) => `<tr>
											<td style="padding:4px 0 4px 28px;color:#9a9a9a;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;">${escapeHtml(account.number)}</td>
											<td align="right" style="padding:4px 0 4px 12px;color:#ececec;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;white-space:nowrap;">${escapeHtml(formatPlain(account.equity))}</td>
										</tr>`
									)
									.join('')
							: '';
					const label =
						name.accounts.length === 1
							? `${escapeHtml(name.name)} <span style="color:#9a9a9a;">${escapeHtml(name.accounts[0].number)}</span>`
							: `${escapeHtml(name.name)} <span style="color:#9a9a9a;">(${name.accounts.length})</span>`;
					return `<tr>
						<td style="padding:6px 0 6px 16px;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;">${label}</td>
						<td align="right" style="padding:6px 0 6px 12px;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;white-space:nowrap;">${escapeHtml(formatPlain(name.equity))}</td>
					</tr>${accounts}`;
				})
				.join('');
			return `<tr>
				<td style="padding:8px 10px;background:#1c1917;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;">${escapeHtml(broker.broker)} <span style="color:#9a9a9a;">(${broker.names.length})</span></td>
				<td align="right" style="padding:8px 10px;background:#1c1917;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;font-weight:650;white-space:nowrap;">${escapeHtml(formatPlain(broker.equity))}</td>
			</tr>${names}`;
		})
		.join('');

	const pendingTotal = data.pending.reduce((sum, item) => sum + item.amount, 0);
	const pendingRows =
		data.pending.length === 0
			? `<tr><td colspan="6" style="padding:18px 8px;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:13px;text-align:center;">No pending withdrawals.</td></tr>`
			: data.pending
					.map(
						(item) => `<tr>
							<td style="padding:8px;border-top:1px solid #2a2a2a;color:#ececec;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;white-space:nowrap;">${escapeHtml(formatStamp(item.withdrawnAt))}</td>
							<td style="padding:8px;border-top:1px solid #2a2a2a;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">${item.unit === 0 ? 'Unknown' : item.unit}</td>
							<td style="padding:8px;border-top:1px solid #2a2a2a;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;">${escapeHtml(item.accountNumber)}</td>
							<td style="padding:8px;border-top:1px solid #2a2a2a;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">${escapeHtml(item.accountName)}</td>
							<td style="padding:8px;border-top:1px solid #2a2a2a;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">${escapeHtml(item.brokerName)}</td>
							<td align="right" style="padding:8px;border-top:1px solid #2a2a2a;color:#f5d76a;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;white-space:nowrap;">${escapeHtml(formatPlain(item.amount))}</td>
						</tr>
						${item.note ? `<tr><td colspan="6" style="padding:0 8px 8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">${escapeHtml(item.note)}</td></tr>` : ''}`
					)
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
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#0a0a0a" style="background:#0a0a0a;">
  <tr>
    <td align="center" style="padding:32px 16px;">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:100%;max-width:560px;">
        <tr>
          <td style="color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:650;letter-spacing:0.14em;text-transform:uppercase;">${escapeHtml(heroLabel)}</td>
        </tr>
        <tr>
          <td style="padding-top:8px;color:${tone(heroValue)};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:42px;font-weight:800;letter-spacing:-0.04em;line-height:1;">${escapeHtml(formatUsd(heroValue))}</td>
        </tr>
        <tr>
          <td style="padding-top:10px;color:#ececec;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;">
            ${
							data.snapshot
								? `Live P/L <span style="color:${tone(data.adjusted)};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-weight:700;">${escapeHtml(formatUsd(data.adjusted))}</span>${adjustedPct === null ? '' : ` <span style="color:${tone(adjustedPct)};">${escapeHtml(formatPercent(adjustedPct))}</span>`}`
								: adjustedPct === null
									? 'Amounts in USD'
									: `<span style="color:${tone(adjustedPct)};font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-weight:700;">${escapeHtml(formatPercent(adjustedPct))}</span>`
						}
          </td>
        </tr>
        <tr>
          <td>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                ${fact('SUM WD', formatUsd(data.sumWd), data.sumWd > 0 ? '#8fd9a4' : '#ececec')}
                ${fact('SUM DP', data.sumDp > 0 ? `-${formatPlain(data.sumDp)}` : formatPlain(data.sumDp), data.sumDp > 0 ? '#f0a0a0' : '#ececec')}
                ${data.snapshot ? fact('Baseline', formatUsd(data.snapshot.baseline), tone(data.snapshot.baseline)) : ''}
              </tr>
            </table>
          </td>
        </tr>
        ${unitBlocks}
        <tr>
          <td style="padding-top:28px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td style="color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:650;letter-spacing:0.14em;text-transform:uppercase;">Total</td>
                <td align="right" style="color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:22px;font-weight:750;">${escapeHtml(formatPlain(data.bookTotal))}</td>
              </tr>
              ${data.initialCapital > 0 ? `<tr><td colspan="2" style="padding-top:4px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">Capital ${escapeHtml(formatPlain(data.initialCapital))}</td></tr>` : ''}
            </table>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:12px;">
              ${brokerRows}
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:28px;">
            <div style="color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:650;">Pending Withdrawals${pendingTotal > 0 ? ` <span style="color:#f5d76a;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;font-weight:650;">${escapeHtml(formatPlain(pendingTotal))}</span>` : ''}</div>
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:10px;border:1px solid #2a2a2a;">
              <tr>
                <th align="left" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Date</th>
                <th align="left" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Unit</th>
                <th align="left" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Account</th>
                <th align="left" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Name</th>
                <th align="left" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Broker</th>
                <th align="right" style="padding:8px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:11px;font-weight:650;">Amount</th>
              </tr>
              ${pendingRows}
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding-top:28px;">
            <div style="color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:16px;font-weight:650;">${escapeHtml(data.wallet.name || 'Wallet')}</div>
            <div style="padding-top:6px;color:#f5f5f5;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:32px;font-weight:800;letter-spacing:-0.03em;">${escapeHtml(formatPlain(data.wallet.balance))}</div>
            ${data.wallet.updatedAt ? `<div style="padding-top:6px;color:#9a9a9a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;">Updated ${escapeHtml(formatStamp(data.wallet.updatedAt))}</div>` : ''}
          </td>
        </tr>
        <tr>
          <td style="padding-top:28px;color:#7a7a7a;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;line-height:1.5;">
            ${escapeHtml(when)} · Asia/Bangkok<br>Amounts in USD · Profit Monitor
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>`;

	return { subject, text: textLines.join('\n'), html };
}
