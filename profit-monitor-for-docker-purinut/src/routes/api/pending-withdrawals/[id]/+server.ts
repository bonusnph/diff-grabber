import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-postgres.js';

export const DELETE: RequestHandler = async ({ params }) => {
	try {
		const id = typeof params.id === 'string' ? params.id.trim() : '';
		if (!id) {
			return json({ error: 'Invalid id' }, { status: 400 });
		}

		const existing = await storage.getPendingWithdrawals();
		const pendingWithdrawals = existing.filter((item) => item.id !== id);
		if (pendingWithdrawals.length === existing.length) {
			return json({ error: 'Pending withdrawal not found' }, { status: 404 });
		}

		await storage.setPendingWithdrawals(pendingWithdrawals);
		return json({ status: 'success', pendingWithdrawals });
	} catch (error) {
		console.error('Error deleting pending withdrawal:', error);
		return json({ error: 'Failed to delete pending withdrawal' }, { status: 500 });
	}
};
