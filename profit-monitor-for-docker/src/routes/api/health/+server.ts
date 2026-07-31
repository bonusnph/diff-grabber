import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	try {
		const stats = await storage.getDashboardStats();
		const dataCount = await storage.getDataCount();
		const uptime = process.uptime();
		
		return json({
			status: 'healthy',
			timestamp: new Date().toISOString(),
			uptime: Math.floor(uptime),
			data: {
				total_records: dataCount,
				active_accounts: stats.account_count,
				total_balance: stats.total_balance
			},
			version: '1.0.0'
		});
		
	} catch (error) {
		console.error('Health check failed:', error);
		return json({
			status: 'unhealthy',
			timestamp: new Date().toISOString(),
			error: 'Internal server error'
		}, { status: 500 });
	}
};
