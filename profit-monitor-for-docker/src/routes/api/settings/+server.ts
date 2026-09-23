import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { storage } from '$lib/storage-postgres.js';
import { schedulePlAlertEvaluation } from '$lib/pl-alerts.js';
import { normalizePlAlertSettings } from '$lib/pl-alert-model.js';
import { normalizeCurrencySettings } from '$lib/currency.js';
import { normalizeExternalWallet } from '$lib/external-wallet-model.js';
import { resolveFxQuote } from '$lib/fx-rate.js';

function normalizeUnitNotes(raw: unknown): Record<number, number> | null {
	if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return null;
	const normalized: Record<number, number> = {};
	for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
		const unit = Number(key);
		const amount = typeof value === 'number' ? value : Number(value);
		if (!Number.isInteger(unit) || !Number.isFinite(amount) || amount <= 0) continue;
		normalized[unit] = Math.round(amount * 100) / 100;
	}
	return normalized;
}

async function settingsPayload() {
	const currency = await storage.getCurrencySettings();
	return {
		initial_capital: await storage.getInitialCapital(),
		unit_initial_capitals: await storage.getUnitInitialCapitals(),
		unit_warning_equity_percentages: await storage.getUnitWarningEquityPercentages(),
		total_active_accounts: await storage.getTotalActiveAccounts(),
		unit_mappings: await storage.getUnitMappings(),
		unit_broker_min_margins: await storage.getUnitBrokerMinMargins(),
		unit_withdrawals: await storage.getUnitWithdrawals(),
		unit_deposits: await storage.getUnitDeposits(),
		external_wallet: await storage.getExternalWallet(),
		snapshot: await storage.getSnapshotPL(),
		pl_alert: await storage.getPlAlertSettings(),
		pl_alert_state: await storage.getPlAlertState(),
		equity_warning_state: await storage.getEquityWarningState(),
		currency,
		fx: await resolveFxQuote(currency)
	};
}

export const GET: RequestHandler = async () => {
	return json(await settingsPayload());
};

export const POST: RequestHandler = async ({ request }) => {
	try {
		const { initial_capital, unit_initial_capitals, total_active_accounts, unit_warning_equity_percentages, unit_mappings, unit_broker_min_margins, unit_withdrawals, unit_deposits, external_wallet, snapshot, clear_snapshot, pl_alert, currency } = await request.json();
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
			const normalized = normalizeUnitNotes(unit_withdrawals);
			if (!normalized) {
				return json({ error: 'Invalid unit withdrawals' }, { status: 400 });
			}
			await storage.setUnitWithdrawals(normalized);
		}

		if (unit_deposits !== undefined) {
			const normalized = normalizeUnitNotes(unit_deposits);
			if (!normalized) {
				return json({ error: 'Invalid unit deposits' }, { status: 400 });
			}
			await storage.setUnitDeposits(normalized);
		}

		if (external_wallet !== undefined) {
			if (typeof external_wallet !== 'object' || external_wallet === null || Array.isArray(external_wallet)) {
				return json({ error: 'Invalid external wallet' }, { status: 400 });
			}
			await storage.setExternalWallet(normalizeExternalWallet(external_wallet));
		}

		if (pl_alert !== undefined) {
			if (typeof pl_alert !== 'object' || pl_alert === null || Array.isArray(pl_alert)) {
				return json({ error: 'Invalid PL alert settings' }, { status: 400 });
			}
			const recipientEmail = typeof pl_alert.recipientEmail === 'string' ? pl_alert.recipientEmail.trim() : '';
			if (recipientEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipientEmail)) {
				return json({ error: 'Invalid alert recipient email' }, { status: 400 });
			}
			await storage.setPlAlertSettings({
				...normalizePlAlertSettings(pl_alert),
				recipientEmail
			});
			schedulePlAlertEvaluation();
		}

		if (currency !== undefined) {
			if (typeof currency !== 'object' || currency === null || Array.isArray(currency)) {
				return json({ error: 'Invalid currency settings' }, { status: 400 });
			}
			await storage.setCurrencySettings(normalizeCurrencySettings(currency));
		}

		return json({
			status: 'success',
			...(await settingsPayload())
		});
		
	} catch (error) {
		console.error('Error updating settings:', error);
		return json({ error: 'Invalid request data' }, { status: 400 });
	}
};
