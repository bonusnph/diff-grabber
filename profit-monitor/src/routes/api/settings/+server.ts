import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	return json({
		initial_capital: await storage.getInitialCapital(),
		capital_per_unit: await storage.getCapitalPerUnit(),
		total_active_accounts: await storage.getTotalActiveAccounts(),
		unit_mappings: await storage.getUnitMappings()
	});
};

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { initial_capital, capital_per_unit, total_active_accounts, unit_mappings } = await request.json();
		
		if (initial_capital !== undefined) {
			if (typeof initial_capital !== 'number' || initial_capital < 0) {
				return json({ error: 'Invalid initial capital amount' }, { status: 400 });
			}
			await storage.setInitialCapital(initial_capital);
		}
		
		if (capital_per_unit !== undefined) {
			if (typeof capital_per_unit !== 'number' || capital_per_unit < 0) {
				return json({ error: 'Invalid capital per unit amount' }, { status: 400 });
			}
			await storage.setCapitalPerUnit(capital_per_unit);
		}

		if (total_active_accounts !== undefined) {
			if (typeof total_active_accounts !== 'number' || total_active_accounts < 1) {
				return json({ error: 'Invalid total active accounts' }, { status: 400 });
			}
			await storage.setTotalActiveAccounts(total_active_accounts);
		}

		if (unit_mappings !== undefined) {
			if (typeof unit_mappings !== 'object' || Array.isArray(unit_mappings)) {
				return json({ error: 'Invalid unit mappings' }, { status: 400 });
			}
			await storage.setUnitMappings(unit_mappings);
		}
		
		return json({ 
			status: 'success',
			initial_capital: await storage.getInitialCapital(),
			capital_per_unit: await storage.getCapitalPerUnit(),
			total_active_accounts: await storage.getTotalActiveAccounts(),
			unit_mappings: await storage.getUnitMappings()
		});
		
	} catch (error) {
		console.error('Error updating settings:', error);
		return json({ error: 'Invalid request data' }, { status: 400 });
	}
};
