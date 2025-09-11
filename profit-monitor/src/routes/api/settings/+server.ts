import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	return json({
		initial_capital: await storage.getInitialCapital(),
		capital_per_unit: await storage.getCapitalPerUnit(),
		total_active_accounts: await storage.getTotalActiveAccounts(),
		warning_equity_percentage: await storage.getWarningEquityPercentage(),
		unit_mappings: await storage.getUnitMappings(),
		broker_min_margins: await storage.getBrokerMinMargins(),
		unit_withdrawals: await storage.getUnitWithdrawals(),
		account_withdrawals: await storage.getAccountWithdrawals()
	});
};

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { initial_capital, capital_per_unit, total_active_accounts, warning_equity_percentage, unit_mappings, broker_min_margins, unit_withdrawals, account_withdrawals } = await request.json();
		
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

		if (warning_equity_percentage !== undefined) {
			if (typeof warning_equity_percentage !== 'number' || warning_equity_percentage < 1 || warning_equity_percentage > 100) {
				return json({ error: 'Invalid warning equity percentage (must be between 1-100)' }, { status: 400 });
			}
			await storage.setWarningEquityPercentage(warning_equity_percentage);
		}

		if (unit_mappings !== undefined) {
			if (typeof unit_mappings !== 'object' || Array.isArray(unit_mappings)) {
				return json({ error: 'Invalid unit mappings' }, { status: 400 });
			}
			await storage.setUnitMappings(unit_mappings);
		}

		if (broker_min_margins !== undefined) {
			if (typeof broker_min_margins !== 'object' || Array.isArray(broker_min_margins)) {
				return json({ error: 'Invalid broker min margins' }, { status: 400 });
			}
			// Validate values are numbers >= 0
			for (const [k, v] of Object.entries(broker_min_margins)) {
				if (typeof v !== 'number' || v < 0) {
					return json({ error: `Invalid margin for broker '${k}'` }, { status: 400 });
				}
			}
			await storage.setBrokerMinMargins(broker_min_margins);
		}

		if (unit_withdrawals !== undefined) {
			if (typeof unit_withdrawals !== 'object' || Array.isArray(unit_withdrawals)) {
				return json({ error: 'Invalid unit withdrawals' }, { status: 400 });
			}
			const normalized: Record<number, number> = {};
			for (const [k, v] of Object.entries(unit_withdrawals)) {
				const unit = parseInt(k as string);
				const num = typeof v === 'number' && isFinite(v) ? v : 0;
				if (!isNaN(unit)) normalized[unit] = num;
			}
			await storage.setUnitWithdrawals(normalized);
		}

		if (account_withdrawals !== undefined) {
			if (typeof account_withdrawals !== 'object' || Array.isArray(account_withdrawals)) {
				return json({ error: 'Invalid account withdrawals' }, { status: 400 });
			}
			const normalizedAcc: Record<string, number> = {};
			for (const [k, v] of Object.entries(account_withdrawals)) {
				const key = String(k);
				const num = typeof v === 'number' && isFinite(v) ? v : 0;
				normalizedAcc[key] = num;
			}
			await storage.setAccountWithdrawals(normalizedAcc);
		}
		
		return json({ 
			status: 'success',
			initial_capital: await storage.getInitialCapital(),
			capital_per_unit: await storage.getCapitalPerUnit(),
			total_active_accounts: await storage.getTotalActiveAccounts(),
			warning_equity_percentage: await storage.getWarningEquityPercentage(),
			unit_mappings: await storage.getUnitMappings(),
			broker_min_margins: await storage.getBrokerMinMargins(),
			unit_withdrawals: await storage.getUnitWithdrawals(),
			account_withdrawals: await storage.getAccountWithdrawals()
		});
		
	} catch (error) {
		console.error('Error updating settings:', error);
		return json({ error: 'Invalid request data' }, { status: 400 });
	}
};
