import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import type { AccountData, OrderInfo } from '$lib/types.js';
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

	// Normalize last position info
	const side = (data.lastPositionSide || 'UNKNOWN').toUpperCase();
	if (side !== 'BUY' && side !== 'SELL') {
		data.lastPositionSide = 'UNKNOWN';
	} else {
		data.lastPositionSide = side as any;
	}
	if (typeof data.lastPositionEntryPrice !== 'number' || !isFinite(data.lastPositionEntryPrice)) {
		data.lastPositionEntryPrice = 0;
	}
	if (typeof data.lastSize !== 'number' || !isFinite(data.lastSize)) {
		data.lastSize = 0;
	}

	// Normalize orders list (open positions)
	if (!Array.isArray(data.orders)) {
		data.orders = [];
	} else {
		const cleaned: OrderInfo[] = [];
		for (const raw of data.orders) {
			if (!raw || typeof raw !== 'object') continue;
			const oSide = String((raw as any).side || '').toUpperCase();
			if (oSide !== 'BUY' && oSide !== 'SELL') continue;
			const price = Number((raw as any).price);
			const lots = Number((raw as any).lots);
			const symbol = String((raw as any).symbol || '').trim();
			const openTime = String((raw as any).openTime || '').trim();
			const magicRaw = (raw as any).magic;
			const magicNum = magicRaw === undefined || magicRaw === null ? NaN : Number(magicRaw);
			if (!isFinite(price) || !isFinite(lots) || !openTime) continue;
			const entry: OrderInfo = {
				symbol,
				side: oSide as 'BUY' | 'SELL',
				price,
				lots,
				openTime
			};
			if (Number.isFinite(magicNum)) {
				entry.magic = magicNum;
			}
			cleaned.push(entry);
		}
		data.orders = cleaned;
	}

	// Backfill latest position fields from orders if not provided by EA
	if ((data.lastPositionSide === 'UNKNOWN' || !data.lastPositionEntryPrice) && data.orders.length > 0) {
		const latest = [...data.orders].sort(
			(a, b) => new Date(b.openTime).getTime() - new Date(a.openTime).getTime()
		)[0];
		if (latest) {
			data.lastPositionSide = latest.side;
			data.lastPositionEntryPrice = latest.price;
			data.lastSize = latest.lots;
		}
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
