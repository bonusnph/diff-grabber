import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { resetEquityWarning, resetPlAlert } from '$lib/pl-alerts.js';

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { kind, unit } = await request.json();
		if (kind === 'profit' || kind === 'loss') {
			const state = await resetPlAlert(kind);
			return json({ status: 'success', state });
		}
		if (kind === 'equity') {
			const parsedUnit = Number(unit);
			if (!Number.isInteger(parsedUnit)) {
				return json({ error: 'Invalid equity warning unit' }, { status: 400 });
			}
			const state = await resetEquityWarning(parsedUnit);
			return json({ status: 'success', equityWarningState: state });
		}
		return json({ error: 'Invalid alert kind' }, { status: 400 });
	} catch (error) {
		console.error('Error resetting alert:', error);
		return json({ error: 'Failed to reset alert' }, { status: 500 });
	}
};
