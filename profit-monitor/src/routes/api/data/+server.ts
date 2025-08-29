import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	try {
		const stats = await storage.getDashboardStats();
		const summaries = await storage.getAccountSummaries();
		const unitGroups = await storage.getAccountsByUnit();
		const unitStats = await storage.getUnitStats();
		
		return json({
			stats,
			summaries,
			unitGroups,
			unitStats
		});
		
	} catch (error) {
		console.error('Error fetching data:', error);
		return json({ error: 'Failed to fetch data' }, { status: 500 });
	}
};
