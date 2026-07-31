import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async ({ params, url }) => {
	try {
		const accountNumber = params.account;
		const limit = parseInt(url.searchParams.get('limit') || '100');
		
		if (!accountNumber) {
			return json({ error: 'Account number is required' }, { status: 400 });
		}
		
		if (limit < 1 || limit > 1000) {
			return json({ error: 'Limit must be between 1 and 1000' }, { status: 400 });
		}
		
		const history = await storage.getAccountHistory(accountNumber, limit);
		
		return json({
			account_number: accountNumber,
			records: history.length,
			data: history
		});
		
	} catch (error) {
		console.error('Error fetching account history:', error);
		return json({ error: 'Failed to fetch account history' }, { status: 500 });
	}
};
