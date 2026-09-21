import type { AccountSummary, PlAlertSettings, PlAlertState } from '$lib/types.js';

export function defaultPlAlertSettings(): PlAlertSettings {
	return {
		profitEnabled: false,
		profitThreshold: 0,
		lossEnabled: false,
		lossThreshold: 0,
		equityWarningEnabled: false,
		recipientEmail: ''
	};
}

export function defaultPlAlertState(): PlAlertState {
	return {
		profitPaused: false,
		lossPaused: false,
		lastProfitSentAt: null,
		lastLossSentAt: null
	};
}

export function normalizePlAlertSettings(raw: unknown): PlAlertSettings {
	const fallback = defaultPlAlertSettings();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	const profitThreshold = Number(value.profitThreshold);
	const lossThreshold = Number(value.lossThreshold);
	const recipientEmail = typeof value.recipientEmail === 'string' ? value.recipientEmail.trim() : '';
	return {
		profitEnabled: value.profitEnabled === true,
		profitThreshold: Number.isFinite(profitThreshold) && profitThreshold > 0 ? profitThreshold : 0,
		lossEnabled: value.lossEnabled === true,
		lossThreshold: Number.isFinite(lossThreshold) && lossThreshold > 0 ? lossThreshold : 0,
		equityWarningEnabled: value.equityWarningEnabled === true,
		recipientEmail
	};
}

export function normalizePlAlertState(raw: unknown): PlAlertState {
	const fallback = defaultPlAlertState();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	return {
		profitPaused: value.profitPaused === true,
		lossPaused: value.lossPaused === true,
		lastProfitSentAt: typeof value.lastProfitSentAt === 'string' ? value.lastProfitSentAt : null,
		lastLossSentAt: typeof value.lastLossSentAt === 'string' ? value.lastLossSentAt : null
	};
}

export function timestampSecondKey(timestamp: string): string {
	const date = new Date(timestamp);
	if (Number.isNaN(date.getTime())) return '';
	return date.toISOString().slice(0, 19);
}

export function isSnapshotReady(summaries: AccountSummary[]): boolean {
	if (!summaries.length) return false;
	const unitCount = new Set(summaries.map((item) => item.unit)).size;
	if (unitCount < 1 || summaries.length < unitCount * 2) return false;
	const keys = summaries.map((item) => timestampSecondKey(item.last_update));
	if (keys.some((key) => !key)) return false;
	return keys.every((key) => key === keys[0]);
}

export function computeAdjustedProfitLoss(
	profitLoss: number,
	withdrawals: Record<string, number>,
	deposits: Record<string, number>
): number {
	const waitingWd = Object.values(withdrawals || {}).reduce(
		(sum, value) => sum + (typeof value === 'number' && Number.isFinite(value) ? value : 0),
		0
	);
	const totalDeposits = Object.values(deposits || {}).reduce(
		(sum, value) => sum + (typeof value === 'number' && Number.isFinite(value) ? value : 0),
		0
	);
	return profitLoss + waitingWd - totalDeposits;
}
