import {
	DEFAULT_FIXED_USDTHB,
	identityFxQuote,
	makeFxQuote,
	normalizeCurrencySettings
} from './currency.js';
import type { FxQuote } from './types.js';

const LIVE_TTL_MS = 15 * 60 * 1000;
const FRANKFURTER_URL = 'https://api.frankfurter.dev/v1/latest?base=USD&symbols=THB';
const OPEN_ER_URL = 'https://open.er-api.com/v6/latest/USD';

let cachedLive: { rate: number; source: string; fetchedAt: string; expiresAt: number } | null = null;

function validRate(value: unknown): number | null {
	const rate = Number(value);
	return Number.isFinite(rate) && rate > 0 ? rate : null;
}

async function fetchJson(url: string): Promise<unknown> {
	const response = await fetch(url, {
		headers: { Accept: 'application/json' }
	});
	if (!response.ok) {
		throw new Error(`FX request failed (${response.status})`);
	}
	return response.json();
}

async function fetchFrankfurter(): Promise<{ rate: number; source: string }> {
	const payload = (await fetchJson(FRANKFURTER_URL)) as { rates?: { THB?: number } };
	const rate = validRate(payload?.rates?.THB);
	if (!rate) throw new Error('Frankfurter rate missing');
	return { rate, source: 'frankfurter' };
}

async function fetchOpenErApi(): Promise<{ rate: number; source: string }> {
	const payload = (await fetchJson(OPEN_ER_URL)) as { rates?: { THB?: number } };
	const rate = validRate(payload?.rates?.THB);
	if (!rate) throw new Error('open.er-api rate missing');
	return { rate, source: 'open-er-api' };
}

async function fetchLiveUsdThb(): Promise<{ rate: number; source: string; fetchedAt: string }> {
	const now = Date.now();
	if (cachedLive && cachedLive.expiresAt > now) {
		return {
			rate: cachedLive.rate,
			source: cachedLive.source,
			fetchedAt: cachedLive.fetchedAt
		};
	}

	let live: { rate: number; source: string };
	try {
		live = await fetchFrankfurter();
	} catch {
		live = await fetchOpenErApi();
	}

	const fetchedAt = new Date().toISOString();
	cachedLive = {
		rate: live.rate,
		source: live.source,
		fetchedAt,
		expiresAt: now + LIVE_TTL_MS
	};
	return { ...live, fetchedAt };
}

export async function resolveFxQuote(rawSettings: unknown): Promise<FxQuote> {
	const settings = normalizeCurrencySettings(rawSettings);
	if (settings.currency === 'USD') {
		return identityFxQuote(settings);
	}
	if (settings.rateMode === 'fixed') {
		return makeFxQuote(settings, settings.fixedRate, 'fixed');
	}

	try {
		const live = await fetchLiveUsdThb();
		return makeFxQuote(settings, live.rate, live.source, live.fetchedAt);
	} catch (error) {
		const fallbackRate =
			cachedLive?.rate ||
			(Number.isFinite(settings.fixedRate) && settings.fixedRate > 0
				? settings.fixedRate
				: DEFAULT_FIXED_USDTHB);
		console.error('Live FX fetch failed, using fallback rate:', error);
		return makeFxQuote(
			settings,
			fallbackRate,
			cachedLive ? `${cachedLive.source}-stale` : 'fixed-fallback',
			cachedLive?.fetchedAt || new Date().toISOString()
		);
	}
}

