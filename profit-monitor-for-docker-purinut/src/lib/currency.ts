import type { CurrencySettings, DisplayCurrency, FxDisplayMode, FxQuote, FxRateMode } from './types.js';

export const DEFAULT_FIXED_USDTHB = 31;

export function defaultCurrencySettings(): CurrencySettings {
	return {
		currency: 'USD',
		rateMode: 'fixed',
		fixedRate: DEFAULT_FIXED_USDTHB,
		liveBuffer: 0
	};
}

export function normalizeCurrencySettings(raw: unknown): CurrencySettings {
	const fallback = defaultCurrencySettings();
	if (!raw || typeof raw !== 'object') return fallback;
	const value = raw as Record<string, unknown>;
	const currency: DisplayCurrency = value.currency === 'THB' ? 'THB' : 'USD';
	const rateMode: FxRateMode = value.rateMode === 'live' ? 'live' : 'fixed';
	const parsedRate = Number(value.fixedRate);
	const fixedRate =
		Number.isFinite(parsedRate) && parsedRate > 0 ? parsedRate : DEFAULT_FIXED_USDTHB;
	const parsedBuffer = Number(value.liveBuffer);
	const liveBuffer = Number.isFinite(parsedBuffer) && parsedBuffer > 0 ? parsedBuffer : 0;
	return { currency, rateMode, fixedRate, liveBuffer };
}

export function fxDisplayMode(settings: CurrencySettings): FxDisplayMode {
	if (settings.rateMode !== 'live') return 'fixed';
	return settings.liveBuffer > 0 ? 'live+buffer' : 'live';
}

export function applyLiveBuffer(rate: number, buffer: number): number {
	const raw = Number(rate);
	if (!Number.isFinite(raw) || raw <= 0) return 0;
	const cut = Number.isFinite(buffer) && buffer > 0 ? buffer : 0;
	const next = raw - cut;
	return next > 0 ? next : 0.01;
}

export function displayRateFor(settings: CurrencySettings, liveRate?: number): number {
	if (settings.currency === 'USD') return 1;
	if (settings.rateMode === 'live') {
		const rate = Number(liveRate);
		if (!Number.isFinite(rate) || rate <= 0) return settings.fixedRate;
		return applyLiveBuffer(rate, settings.liveBuffer);
	}
	return settings.fixedRate;
}

export function convertUsd(amount: number, rate: number): number {
	const safeRate = Number.isFinite(rate) && rate > 0 ? rate : 1;
	return amount * safeRate;
}

export function makeFxQuote(
	settings: CurrencySettings,
	rawRate: number,
	source: string,
	fetchedAt = new Date().toISOString()
): FxQuote {
	const buffered = settings.rateMode === 'live' ? applyLiveBuffer(rawRate, settings.liveBuffer) : rawRate;
	const rate = settings.currency === 'USD' ? 1 : buffered;
	return {
		currency: settings.currency,
		rate,
		rawRate: settings.currency === 'USD' ? 1 : rawRate,
		buffer: settings.rateMode === 'live' ? settings.liveBuffer : 0,
		mode: settings.rateMode,
		displayMode: fxDisplayMode(settings),
		source,
		fetchedAt
	};
}

export function identityFxQuote(settings: CurrencySettings): FxQuote {
	const raw = settings.currency === 'USD' ? 1 : settings.fixedRate;
	return makeFxQuote(settings, raw, settings.currency === 'USD' ? 'identity' : 'fixed');
}
