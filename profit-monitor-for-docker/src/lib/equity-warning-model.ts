import type { AccountSummary, EquityWarningState } from '$lib/types.js';

export const DEFAULT_UNIT_WARNING_PCT = 30;
export const EQUITY_WARNING_FRESH_MS = 5 * 60 * 1000;

export function defaultEquityWarningState(): EquityWarningState {
	return { pausedUnits: {} };
}

export function normalizeEquityWarningState(raw: unknown): EquityWarningState {
	const fallback = defaultEquityWarningState();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	const pausedRaw = value.pausedUnits;
	if (!pausedRaw || typeof pausedRaw !== 'object' || Array.isArray(pausedRaw)) return fallback;
	const pausedUnits: Record<number, string> = {};
	for (const [key, sentAt] of Object.entries(pausedRaw)) {
		const unit = Number(key);
		if (!Number.isInteger(unit) || typeof sentAt !== 'string' || !sentAt) continue;
		pausedUnits[unit] = sentAt;
	}
	return { pausedUnits };
}

export function getUnitTargetEquity(unitCapital: number): number {
	return unitCapital / 2;
}

export function getUnitWarningPct(warnPct: number | undefined): number {
	return typeof warnPct === 'number' && warnPct >= 1 && warnPct <= 100
		? warnPct
		: DEFAULT_UNIT_WARNING_PCT;
}

export function getWarningThreshold(unitCapital: number, warnPct: number | undefined): number {
	return getUnitTargetEquity(unitCapital) * (getUnitWarningPct(warnPct) / 100);
}

export function isLowEquityWarning(
	equity: number,
	unitCapital: number,
	warnPct: number | undefined
): boolean {
	if (!(unitCapital > 0)) return false;
	return equity < getWarningThreshold(unitCapital, warnPct);
}

export function isAccountFresh(lastUpdate: string, now = Date.now()): boolean {
	const time = new Date(lastUpdate).getTime();
	if (Number.isNaN(time)) return false;
	return now - time < EQUITY_WARNING_FRESH_MS;
}

export function isEquityWarningPaused(state: EquityWarningState, unit: number): boolean {
	const sentAt = state.pausedUnits[unit] ?? (state.pausedUnits as Record<string, string>)[String(unit)];
	return typeof sentAt === 'string' && sentAt.length > 0;
}

export type EquityMeterZone = 'unset' | 'breach' | 'near' | 'ok' | 'over';

export interface EquityMeter {
	zone: EquityMeterZone;
	/** Fill of the main chamber, 0–100. 100 means equity is at the target. */
	fillPct: number;
	/** Warning tick position on the main chamber, 0–100. */
	warnPct: number;
	/** Fill of the overflow lip, 0–100. 100 means excess is at least one full target. */
	overPct: number;
	/** Non-negative amount for the caption: depth past warning, cushion to warning, surplus, or gap to target. */
	mark: number;
}

const EQUITY_METER_NEAR_BAND = 0.15;

export function equityMeter(
	equity: number,
	unitCapital: number,
	warnPct: number | undefined
): EquityMeter {
	const target = getUnitTargetEquity(unitCapital);
	const tick = getUnitWarningPct(warnPct);
	if (!(target > 0) || !Number.isFinite(equity)) {
		return { zone: 'unset', fillPct: 0, warnPct: tick, overPct: 0, mark: 0 };
	}
	const warn = getWarningThreshold(unitCapital, warnPct);
	const over = Math.max(0, equity - target);
	const fillPct = Math.max(0, Math.min(100, (Math.min(Math.max(equity, 0), target) / target) * 100));
	const overPct = Math.max(0, Math.min(100, (over / target) * 100));
	if (isLowEquityWarning(equity, unitCapital, warnPct)) {
		return { zone: 'breach', fillPct, warnPct: tick, overPct: 0, mark: Math.max(0, warn - equity) };
	}
	if (over > 0.005) {
		return { zone: 'over', fillPct: 100, warnPct: tick, overPct, mark: over };
	}
	const cushion = Math.max(0, equity - warn);
	if (cushion / target < EQUITY_METER_NEAR_BAND) {
		return { zone: 'near', fillPct, warnPct: tick, overPct: 0, mark: cushion };
	}
	return { zone: 'ok', fillPct, warnPct: tick, overPct: 0, mark: Math.max(0, target - equity) };
}

export function findLowEquityAccounts(
	accounts: AccountSummary[],
	unitCapital: number,
	warnPct: number | undefined,
	now = Date.now()
): AccountSummary[] {
	return accounts.filter(
		(account) =>
			isAccountFresh(account.last_update, now) &&
			isLowEquityWarning(account.latest_equity, unitCapital, warnPct)
	);
}
