import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { AccountData } from '$lib/types.js';
import { storage } from '$lib/storage-supabase.js';

export const POST: RequestHandler = async ({ request }) => {
	try {
		const data: AccountData = await request.json();
		
		// Validate required fields
		if (!data.account_number || !data.broker_name || 
			typeof data.balance !== 'number' || typeof data.equity !== 'number') {
			return json({ error: 'Missing required fields' }, { status: 400 });
		}

		// Set default unit if not provided
		if (typeof data.unit !== 'number') {
			data.unit = 1;
		}

		// Add timestamp if not provided (store in UTC; format to Asia/Bangkok on UI)
		if (!data.timestamp) {
			data.timestamp = new Date().toISOString();
		}

		// Ensure account_name is present to satisfy NOT NULL constraint
		if (!data.account_name || data.account_name.trim() === '') {
			data.account_name = data.account_number;
		}


		// Store data into Supabase
		await storage.addAccountData(data);
		
		console.log(`Received data from ${data.broker_name} - Account: ${data.account_number}, Unit: ${data.unit}, Balance: ${data.balance}`);
		
		return json({ 
			status: 'success',
			message: 'Account data received',
			timestamp: data.timestamp
		});
		
	} catch (error) {
		console.error('Error processing webhook:', error);
		return json({ error: 'Invalid JSON data' }, { status: 400 });
	}
};
