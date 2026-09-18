import { storage } from '$lib/storage-supabase.js';
import { sendAlertEmail } from '$lib/mailer.js';
import type { PlAlertState } from '$lib/types.js';
import { computeAdjustedProfitLoss, isSnapshotReady } from '$lib/pl-alert-model.js';
import { buildPlAlertEmail } from '$lib/pl-alert-email.js';

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
	} catch (error) {
		console.error('PL alert evaluation failed:', error);
	} finally {
		evaluating = false;
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
