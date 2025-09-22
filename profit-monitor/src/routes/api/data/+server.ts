import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	try {
		const stats = await storage.getDashboardStats();
		const summaries = await storage.getAccountSummaries();
		const unitGroups = await storage.getAccountsByUnit();
		const unitStats = await storage.getUnitStats();
		const accountWithdrawals = await storage.getAccountWithdrawals();
		const snapshot = await storage.getSnapshotPL();
		console.log('API /api/data - Retrieved snapshot from storage:', snapshot);
		
		const currentAdjusted = (() => {
			const totalWaitingWD = Object.values(accountWithdrawals || {}).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
			return (stats?.profit_loss || 0) + (totalWaitingWD || 0);
		})();
		const snapshotDelta = snapshot
			? currentAdjusted - (snapshot.kind === 'adjusted' ? snapshot.value : stats.profit_loss)
			: null;
		
		return json({
			stats,
			summaries,
			unitGroups,
			unitStats,
			accountWithdrawals,
			snapshot: snapshot ? { kind: snapshot.kind, value: snapshot.value, timestamp: snapshot.timestamp } : null,
			snapshotDelta
		});
		
	} catch (error) {
		console.error('Error fetching data:', error);
		return json({ error: 'Failed to fetch data' }, { status: 500 });
	}
};
