import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-supabase.js';

export const GET: RequestHandler = async () => {
	return json({
		initial_capital: await storage.getInitialCapital(),
		unit_initial_capitals: await storage.getUnitInitialCapitals(),
		unit_warning_equity_percentages: await storage.getUnitWarningEquityPercentages(),
		total_active_accounts: await storage.getTotalActiveAccounts(),
		unit_mappings: await storage.getUnitMappings(),
		unit_broker_min_margins: await storage.getUnitBrokerMinMargins(),
		unit_withdrawals: await storage.getUnitWithdrawals(),
		account_withdrawals: await storage.getAccountWithdrawals(),
		account_deposits: await storage.getAccountDeposits(),
		snapshot: await storage.getSnapshotPL()
	});
};

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { initial_capital, unit_initial_capitals, total_active_accounts, unit_warning_equity_percentages, unit_mappings, unit_broker_min_margins, unit_withdrawals, account_withdrawals, account_deposits, snapshot, clear_snapshot } = await request.json();
		// Snapshot operations (optional)
		if (clear_snapshot === true) {
			console.log('Clearing snapshot from database...');
			await storage.clearSnapshotPL();
			console.log('Snapshot cleared successfully');
		}

		if (snapshot !== undefined) {
			if (typeof snapshot?.value !== 'number' || (snapshot?.kind !== 'adjusted' && snapshot?.kind !== 'real')) {
				return json({ error: 'Invalid snapshot payload' }, { status: 400 });
			}
			await storage.setSnapshotPL({ value: snapshot.value, kind: snapshot.kind });
		}
		
		// initial_capital is now derived; keep for backward compatibility but ignore if provided
		
		if (unit_initial_capitals !== undefined) {
			if (typeof unit_initial_capitals !== 'object' || Array.isArray(unit_initial_capitals)) {
				return json({ error: 'Invalid unit initial capitals' }, { status: 400 });
			}
			const normalized: Record<number, number> = {};
			for (const [k, v] of Object.entries(unit_initial_capitals)) {
				const unit = parseInt(k as string);
				const num = typeof v === 'number' && v >= 0 ? v : 0;
				if (!isNaN(unit)) normalized[unit] = num;
			}
			await storage.setUnitInitialCapitals(normalized);
		}

		if (total_active_accounts !== undefined) {
			if (typeof total_active_accounts !== 'number' || total_active_accounts < 1) {
				return json({ error: 'Invalid total active accounts' }, { status: 400 });
			}
			await storage.setTotalActiveAccounts(total_active_accounts);
		}

		if (unit_warning_equity_percentages !== undefined) {
			if (typeof unit_warning_equity_percentages !== 'object' || Array.isArray(unit_warning_equity_percentages)) {
				return json({ error: 'Invalid unit warning equity percentages' }, { status: 400 });
			}
			const normalizedWarn: Record<number, number> = {};
			for (const [k, v] of Object.entries(unit_warning_equity_percentages)) {
				const unit = parseInt(k as string);
				const num = typeof v === 'number' && v >= 1 && v <= 100 ? v : 30;
				if (!isNaN(unit)) normalizedWarn[unit] = num;
			}
			await storage.setUnitWarningEquityPercentages(normalizedWarn);
		}

		if (unit_mappings !== undefined) {
			if (typeof unit_mappings !== 'object' || Array.isArray(unit_mappings)) {
				return json({ error: 'Invalid unit mappings' }, { status: 400 });
			}
			await storage.setUnitMappings(unit_mappings);
		}


		if (unit_broker_min_margins !== undefined) {
			if (typeof unit_broker_min_margins !== 'object' || Array.isArray(unit_broker_min_margins)) {
				return json({ error: 'Invalid unit broker min margins' }, { status: 400 });
			}
			// Validate structure: Record<unit, Record<broker_name, min_margin>>
			const normalized: Record<number, Record<string, number>> = {};
			for (const [unitStr, brokerMargins] of Object.entries(unit_broker_min_margins)) {
				const unit = parseInt(unitStr);
				if (isNaN(unit)) continue;
				
				if (typeof brokerMargins !== 'object' || Array.isArray(brokerMargins) || brokerMargins === null) {
					return json({ error: `Invalid broker margins for unit ${unit}` }, { status: 400 });
				}
				
				const brokerMap: Record<string, number> = {};
				for (const [brokerName, margin] of Object.entries(brokerMargins)) {
					if (typeof margin !== 'number' || margin < 0) {
						return json({ error: `Invalid margin for broker '${brokerName}' in unit ${unit}` }, { status: 400 });
					}
					brokerMap[brokerName] = margin;
				}
				normalized[unit] = brokerMap;
			}
			await storage.setUnitBrokerMinMargins(normalized);
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

		if (account_deposits !== undefined) {
			if (typeof account_deposits !== 'object' || Array.isArray(account_deposits)) {
				return json({ error: 'Invalid account deposits' }, { status: 400 });
			}
			const normalizedDep: Record<string, number> = {};
			for (const [k, v] of Object.entries(account_deposits)) {
				const key = String(k);
				const num = typeof v === 'number' && isFinite(v) ? v : 0;
				normalizedDep[key] = num;
			}
			await storage.setAccountDeposits(normalizedDep);
		}
		
		return json({ 
			status: 'success',
			initial_capital: await storage.getInitialCapital(),
			unit_initial_capitals: await storage.getUnitInitialCapitals(),
			unit_warning_equity_percentages: await storage.getUnitWarningEquityPercentages(),
			total_active_accounts: await storage.getTotalActiveAccounts(),
			unit_mappings: await storage.getUnitMappings(),
			unit_broker_min_margins: await storage.getUnitBrokerMinMargins(),
			unit_withdrawals: await storage.getUnitWithdrawals(),
			account_withdrawals: await storage.getAccountWithdrawals(),
			account_deposits: await storage.getAccountDeposits(),
			snapshot: await storage.getSnapshotPL()
		});
		
	} catch (error) {
		console.error('Error updating settings:', error);
		return json({ error: 'Invalid request data' }, { status: 400 });
	}
};
