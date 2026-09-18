import { storage } from '$lib/storage-supabase.js';
import { sendAlertEmail } from '$lib/mailer.js';
import type { PlAlertState } from '$lib/types.js';
import { computeAdjustedProfitLoss, isSnapshotReady } from '$lib/pl-alert-model.js';
import { buildPlAlertEmail } from '$lib/pl-alert-email.js';

export const PL_ALERT_DEBOUNCE_MS = 10_000;

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let evaluating = false;

export function schedulePlAlertEvaluation(): void {
	if (debounceTimer) clearTimeout(debounceTimer);
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
		if (!settings.profitEnabled && !settings.lossEnabled) return;
		if (!settings.recipientEmail) return;

		const summaries = await storage.getAccountSummaries();
		if (!isSnapshotReady(summaries)) return;

		const stats = await storage.getDashboardStats();
		const withdrawals = await storage.getAccountWithdrawals();
		const deposits = await storage.getAccountDeposits();
		const adjusted = computeAdjustedProfitLoss(stats.profit_loss, withdrawals, deposits);
		const state = await storage.getPlAlertState();
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
