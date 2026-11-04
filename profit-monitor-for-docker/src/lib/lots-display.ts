import type { LotsDisplaySettings } from './types.js';

export const DEFAULT_FIXED_LOTS = 0.01;
export const MAX_FIXED_LOTS = 100;

export function defaultLotsDisplay(): LotsDisplaySettings {
	return { enabled: false, lots: DEFAULT_FIXED_LOTS };
}

export function normalizeLotsDisplay(raw: unknown): LotsDisplaySettings {
	const fallback = defaultLotsDisplay();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	const parsed = Number(value.lots);
	const rounded = Number.isFinite(parsed) ? Math.round(parsed * 100) / 100 : DEFAULT_FIXED_LOTS;
	const lots = rounded > 0 && rounded <= MAX_FIXED_LOTS ? rounded : DEFAULT_FIXED_LOTS;
	return {
		enabled: value.enabled === true,
		lots
	};
}
