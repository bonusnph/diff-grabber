import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-postgres.js';
import {
	createPendingWithdrawalId,
	normalizePendingNote,
	parsePendingAmount,
	parsePendingTimestamp
} from '$lib/pending-withdrawal-model.js';
import type { PendingWithdrawal } from '$lib/types.js';

export const POST: RequestHandler = async ({ request }) => {
	try {
		const body = await request.json();
		const accountNumber = typeof body?.account_number === 'string' ? body.account_number.trim() : '';
		const amount = parsePendingAmount(body?.amount);
		if (!accountNumber) {
			return json({ error: 'Invalid account number' }, { status: 400 });
		}
		if (amount === null) {
			return json({ error: 'Invalid amount' }, { status: 400 });
		}

		const summaries = await storage.getAccountSummaries();
		const account = summaries.find((item) => item.account_number === accountNumber);
		if (!account) {
			return json({ error: 'Account not found' }, { status: 404 });
		}

		const now = new Date().toISOString();
		const entry: PendingWithdrawal = {
			id: createPendingWithdrawalId(),
			account_number: account.account_number,
			account_name: account.account_name,
			broker_name: account.broker_name,
			unit: account.unit,
			amount,
			note: normalizePendingNote(body?.note),
			withdrawn_at: parsePendingTimestamp(body?.withdrawn_at, now),
			created_at: now
		};

		const existing = await storage.getPendingWithdrawals();
		const pendingWithdrawals = [entry, ...existing];
		await storage.setPendingWithdrawals(pendingWithdrawals);
		return json({ status: 'success', entry, pendingWithdrawals });
	} catch (error) {
		console.error('Error creating pending withdrawal:', error);
		return json({ error: 'Failed to create pending withdrawal' }, { status: 500 });
	}
};
