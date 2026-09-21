import { storage } from '$lib/storage-postgres.js';
import { sendAlertEmail } from '$lib/mailer.js';
import type { EquityWarningState, PlAlertState } from '$lib/types.js';
import { computeAdjustedProfitLoss, isSnapshotReady } from '$lib/pl-alert-model.js';
import { buildPlAlertEmail } from '$lib/pl-alert-email.js';
import { buildEquityWarningEmail } from '$lib/equity-warning-email.js';
import {
	findLowEquityAccounts,
	getUnitWarningPct,
	getWarningThreshold,
	isEquityWarningPaused
} from '$lib/equity-warning-model.js';

export const PL_ALERT_DEBOUNCE_MS = 10_000;

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let evaluating = false;

export function schedulePlAlertEvaluation(): void {
	if (debounceTimer) return;
	debounceTimer = setTimeout(() => {
		debounceTimer = null;
		void runPlAlertEvaluation();
	}, PL_ALERT_DEBOUNCE_MS);
}

export async function runPlAlertEvaluation(): Promise<void> {
	if (evaluating) return;
	evaluating = true;
	try {
		await evaluatePlAlerts();
		await evaluateEquityWarnings();
	} catch (error) {
		console.error('Alert evaluation failed:', error);
	} finally {
		evaluating = false;
	}
}

async function evaluatePlAlerts(): Promise<void> {
	const settings = await storage.getPlAlertSettings();
	if (!settings.profitEnabled && !settings.lossEnabled) {
		console.log('PL alert skip: disabled');
		return;
	}
	if (!settings.recipientEmail) {
		console.log('PL alert skip: no recipient');
		return;
	}

	const summaries = await storage.getAccountSummaries();
	if (!isSnapshotReady(summaries)) {
		const units = new Set(summaries.map((item) => item.unit)).size;
		console.log(`PL alert skip: snapshot not ready (accounts=${summaries.length}, units=${units})`);
		return;
	}

	const stats = await storage.getDashboardStats();
	const withdrawals = await storage.getAccountWithdrawals();
	const deposits = await storage.getAccountDeposits();
	const adjusted = computeAdjustedProfitLoss(stats.profit_loss, withdrawals, deposits);
	const state = await storage.getPlAlertState();
	console.log(
		`PL alert check adjusted=${adjusted.toFixed(2)} profit=${settings.profitThreshold} loss=${settings.lossThreshold} paused=${state.profitPaused}/${state.lossPaused}`
	);
	const next: PlAlertState = { ...state };

	if (
		settings.profitEnabled &&
		!state.profitPaused &&
		settings.profitThreshold > 0 &&
		adjusted >= settings.profitThreshold
	) {
		const mail = buildPlAlertEmail('profit', adjusted, settings.profitThreshold);
		const sent = await sendAlertEmail(settings.recipientEmail, mail);
		if (sent) {
			next.profitPaused = true;
			next.lastProfitSentAt = new Date().toISOString();
			console.log('PL alert sent: profit');
		}
	}

	if (
		settings.lossEnabled &&
		!state.lossPaused &&
		settings.lossThreshold > 0 &&
		adjusted <= -settings.lossThreshold
	) {
		const mail = buildPlAlertEmail('loss', adjusted, settings.lossThreshold);
		const sent = await sendAlertEmail(settings.recipientEmail, mail);
		if (sent) {
			next.lossPaused = true;
			next.lastLossSentAt = new Date().toISOString();
			console.log('PL alert sent: loss');
		}
	}

	if (next.profitPaused !== state.profitPaused || next.lossPaused !== state.lossPaused) {
		await storage.setPlAlertState(next);
	}
}

async function evaluateEquityWarnings(): Promise<void> {
	const settings = await storage.getPlAlertSettings();
	if (!settings.equityWarningEnabled) {
		console.log('Equity warning skip: disabled');
		return;
	}
	if (!settings.recipientEmail) {
		console.log('Equity warning skip: no recipient');
		return;
	}

	const unitGroups = await storage.getAccountsByUnit();
	const unitCapitals = await storage.getUnitInitialCapitals();
	const warnPercentages = await storage.getUnitWarningEquityPercentages();
	const unitMappings = await storage.getUnitMappings();
	const state = await storage.getEquityWarningState();
	const next: EquityWarningState = { pausedUnits: { ...state.pausedUnits } };
	const now = Date.now();
	let changed = false;

	for (const [unitStr, accounts] of Object.entries(unitGroups)) {
		const unit = Number(unitStr);
		if (!Number.isInteger(unit) || isEquityWarningPaused(next, unit)) continue;
		const unitCapital = unitCapitals[unit] ?? 0;
		if (!(unitCapital > 0)) continue;
		const warnPct = getUnitWarningPct(warnPercentages[unit]);
		const lowAccounts = findLowEquityAccounts(accounts, unitCapital, warnPct, now);
		if (!lowAccounts.length) continue;

		const threshold = getWarningThreshold(unitCapital, warnPct);
		const unitName = unitMappings[unit] || `Unit ${unit}`;
		const mail = buildEquityWarningEmail({
			unit,
			unitName,
			warnPct,
			accounts: lowAccounts.map((account) => ({
				accountNumber: account.account_number,
				accountName: account.account_name,
				brokerName: account.broker_name,
				equity: account.latest_equity,
				threshold
			}))
		});
		const sent = await sendAlertEmail(settings.recipientEmail, mail);
		if (sent) {
			next.pausedUnits[unit] = new Date().toISOString();
			changed = true;
			console.log(`Equity warning sent: unit ${unit}`);
		}
	}

	if (changed) {
		await storage.setEquityWarningState(next);
	}
}

export async function resetPlAlert(kind: 'profit' | 'loss'): Promise<PlAlertState> {
	const state = await storage.getPlAlertState();
	const next: PlAlertState = { ...state };
	if (kind === 'profit') {
		next.profitPaused = false;
		next.lastProfitSentAt = null;
	} else {
		next.lossPaused = false;
		next.lastLossSentAt = null;
	}
	await storage.setPlAlertState(next);
	return next;
}

export async function resetEquityWarning(unit: number): Promise<EquityWarningState> {
	const state = await storage.getEquityWarningState();
	const next: EquityWarningState = { pausedUnits: { ...state.pausedUnits } };
	delete next.pausedUnits[unit];
	delete (next.pausedUnits as Record<string, string>)[String(unit)];
	await storage.setEquityWarningState(next);
	return next;
}
