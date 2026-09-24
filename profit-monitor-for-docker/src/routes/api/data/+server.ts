import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-postgres.js';
import { resolveFxQuote } from '$lib/fx-rate.js';

export const GET: RequestHandler = async () => {
	try {
		const stats = await storage.getDashboardStats();
		const summaries = await storage.getAccountSummaries();
		const unitGroups = await storage.getAccountsByUnit();
		const unitStats = await storage.getUnitStats();
		const unitWithdrawals = await storage.getUnitWithdrawals();
		const unitDeposits = await storage.getUnitDeposits();
		const pendingWithdrawals = await storage.getPendingWithdrawals();
		const externalWallet = await storage.getExternalWallet();
		const snapshot = await storage.getSnapshotPL();
		const plAlertState = await storage.getPlAlertState();
		const plAlertSettings = await storage.getPlAlertSettings();
		const equityWarningState = await storage.getEquityWarningState();
		const unitInitialCapitals = await storage.getUnitInitialCapitals();
		const unitWarningEquityPercentages = await storage.getUnitWarningEquityPercentages();
		const currency = await storage.getCurrencySettings();
		const fx = await resolveFxQuote(currency);
		
		const currentAdjusted = (() => {
			const totalWaitingWD = Object.values(unitWithdrawals || {}).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
			const totalDeposits = Object.values(unitDeposits || {}).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
			return (stats?.profit_loss || 0) + (totalWaitingWD || 0) - (totalDeposits || 0);
		})();
		const snapshotDelta = snapshot
			? currentAdjusted - (snapshot.kind === 'adjusted' ? snapshot.value : stats.profit_loss)
			: null;
		
		return json({
			stats,
			summaries,
			unitGroups,
			unitStats,
			unitWithdrawals,
			unitDeposits,
			pendingWithdrawals,
			externalWallet,
			snapshot: snapshot ? { kind: snapshot.kind, value: snapshot.value, timestamp: snapshot.timestamp } : null,
			snapshotDelta,
			plAlert: {
				settings: plAlertSettings,
				state: plAlertState
			},
			equityWarning: {
				state: equityWarningState
			},
			unitInitialCapitals,
			unitWarningEquityPercentages,
			currency,
			fx
		});
		
	} catch (error) {
		console.error('Error fetching data:', error);
		return json({ error: 'Failed to fetch data' }, { status: 500 });
	}
};
