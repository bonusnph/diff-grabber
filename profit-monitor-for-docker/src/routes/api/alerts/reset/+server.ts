import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { resetPlAlert } from '$lib/pl-alerts.js';

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { kind } = await request.json();
		if (kind !== 'profit' && kind !== 'loss') {
			return json({ error: 'Invalid alert kind' }, { status: 400 });
		}
		const state = await resetPlAlert(kind);
		return json({ status: 'success', state });
	} catch (error) {
		console.error('Error resetting PL alert:', error);
		return json({ error: 'Failed to reset alert' }, { status: 500 });
	}
};
