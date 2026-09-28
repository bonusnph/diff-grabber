import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { sendAlertEmail } from '$lib/mailer.js';
import { buildSummaryEmail, type SummaryEmailUnit } from '$lib/summary-email.js';
import { storage } from '$lib/storage-postgres.js';

function noteTotal(notes: Record<number, number> | undefined): number {
	return Object.values(notes || {}).reduce(
		(sum, value) => sum + (typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0),
		0
	);
}

function noteAmount(notes: Record<number, number> | undefined, unit: number): number {
	const value = notes?.[unit] ?? (notes as Record<string, number> | undefined)?.[String(unit)];
	return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
}

function mappingName(mappings: Record<number, string>, unit: number): string {
	const record = mappings as Record<string, string>;
	const name = record[unit] || record[String(unit)] || '';
	const trimmed = typeof name === 'string' ? name.trim() : '';
	if (trimmed) return trimmed;
	return unit === 0 ? 'Unknown' : `Unit ${unit}`;
}

export const POST: RequestHandler = async () => {
	try {
		const settings = await storage.getPlAlertSettings();
		const to = settings.recipientEmail.trim();
		if (!to) {
			return json({ error: 'No recipient email' }, { status: 400 });
		}

		const stats = await storage.getDashboardStats();
		const grouped = await storage.getAccountsByUnit();
		const unitStats = await storage.getUnitStats();
		const unitWithdrawals = await storage.getUnitWithdrawals();
		const unitDeposits = await storage.getUnitDeposits();
		const pendingWithdrawals = await storage.getPendingWithdrawals();
		const mappings = await storage.getUnitMappings();
		const capitals = await storage.getUnitInitialCapitals();
		const snapshot = await storage.getSnapshotPL();
		const summaries = await storage.getAccountSummaries();
		const wallet = await storage.getExternalWallet();

		const sumWd = noteTotal(unitWithdrawals);
		const sumDp = noteTotal(unitDeposits);
		const adjusted = (stats?.profit_loss || 0) + sumWd - sumDp;
		const snapshotDelta = snapshot
			? adjusted - (snapshot.kind === 'adjusted' ? snapshot.value : stats.profit_loss)
			: null;

		const units: SummaryEmailUnit[] = Object.entries(grouped)
			.map(([unitStr, accounts]) => {
				const unit = Number(unitStr);
				const stat = unitStats.find((item) => item.unit === unit);
				const pending = pendingWithdrawals
					.filter((item) => item.unit === unit)
					.reduce((sum, item) => sum + item.amount, 0);
				return {
					unit,
					name: mappingName(mappings, unit),
					capital: capitals[unit] ?? (capitals as Record<string, number>)[unitStr] ?? 0,
					totalBalance: stat?.totalBalance ?? accounts.reduce((sum, account) => sum + account.latest_balance, 0),
					profitLoss: stat?.profitLoss ?? 0,
					wd: noteAmount(unitWithdrawals, unit),
					dp: noteAmount(unitDeposits, unit),
					pending,
					accounts: [...accounts]
						.sort(
							(a, b) =>
								a.broker_name.localeCompare(b.broker_name) ||
								a.account_number.localeCompare(b.account_number)
						)
						.map((account) => ({
							accountNumber: account.account_number,
							accountName: account.account_name,
							brokerName: account.broker_name,
							balance: account.latest_balance,
							equity: account.latest_equity
						}))
				};
			})
			.sort((a, b) => a.unit - b.unit);

		const brokerMap = new Map<string, { equity: number; names: Map<string, { equity: number; accounts: { number: string; equity: number }[] }> }>();
		for (const account of summaries) {
			const broker = account.broker_name || 'Unknown';
			const name = account.account_name || 'Unknown';
			let group = brokerMap.get(broker);
			if (!group) {
				group = { equity: 0, names: new Map() };
				brokerMap.set(broker, group);
			}
			let named = group.names.get(name);
			if (!named) {
				named = { equity: 0, accounts: [] };
				group.names.set(name, named);
			}
			group.equity += account.latest_equity;
			named.equity += account.latest_equity;
			named.accounts.push({ number: account.account_number, equity: account.latest_equity });
		}
		const brokers = [...brokerMap.entries()]
			.sort((a, b) => b[1].equity - a[1].equity)
			.map(([broker, group]) => ({
				broker,
				equity: group.equity,
				names: [...group.names.entries()]
					.sort((a, b) => b[1].equity - a[1].equity)
					.map(([name, named]) => ({
						name,
						equity: named.equity,
						accounts: [...named.accounts].sort((a, b) => b.equity - a.equity)
					}))
			}));

		const mail = buildSummaryEmail({
			at: new Date(),
			adjusted,
			initialCapital: stats?.initial_capital || 0,
			bookTotal: unitStats.reduce((sum, item) => sum + item.totalBalance, 0),
			sumWd,
			sumDp,
			snapshot:
				snapshot && snapshotDelta !== null
					? {
							baseline: snapshot.kind === 'adjusted' ? snapshot.value : stats.profit_loss,
							delta: snapshotDelta
						}
					: null,
			units,
			brokers,
			pending: [...pendingWithdrawals]
				.sort((a, b) => new Date(b.withdrawn_at).getTime() - new Date(a.withdrawn_at).getTime())
				.map((item) => ({
					withdrawnAt: item.withdrawn_at,
					unit: item.unit,
					accountNumber: item.account_number,
					accountName: item.account_name,
					brokerName: item.broker_name,
					amount: item.amount,
					note: item.note
				})),
			wallet: {
				name: wallet.name,
				balance: wallet.balance,
				updatedAt: wallet.updated_at
			}
		});

		const sent = await sendAlertEmail(to, mail);
		if (!sent) {
			return json({ error: 'Failed to send email' }, { status: 500 });
		}
		return json({ ok: true });
	} catch (error) {
		console.error('Error sending summary email:', error);
		return json({ error: 'Failed to send email' }, { status: 500 });
	}
};
