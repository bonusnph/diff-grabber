<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import {
		convertUsd,
		defaultCurrencySettings,
		identityFxQuote,
		normalizeCurrencySettings
	} from '$lib/currency.js';
	import CurrencyFlag from '$lib/CurrencyFlag.svelte';
	import { listDisplayPairs, splitSignedPairs } from '$lib/pairs.js';
	import { computeAdjustedProfitLoss } from '$lib/pl-alert-model.js';
	import type { AccountSummary, CurrencySettings, FxQuote } from '$lib/types.js';

	const STALE_FORCE_REFRESH_MS = 30 * 1000;
	const CACHE_KEY = 'pm-watch-last';

	type WatchSnapshot = { value: number; kind: 'adjusted' | 'real'; timestamp: string };

	type WatchPayload = {
		stats?: { profit_loss?: number; initial_capital?: number };
		summaries?: Array<{ last_update?: string }>;
		accountWithdrawals?: Record<string, number>;
		accountDeposits?: Record<string, number>;
		unitGroups?: Record<string, AccountSummary[]>;
		currency?: unknown;
		fx?: FxQuote | null;
		snapshot?: WatchSnapshot | null;
		snapshotDelta?: number | null;
	};

	export let data: { initial: WatchPayload | null };

	let loading = true;
	let hasValue = false;
	let failed = false;
	let adjusted = 0;
	let initialCapital = 0;
	let snapshot: WatchSnapshot | null = null;
	let snapshotDelta: number | null = null;
	let snapshotLoading = false;
	let unitGroups: Record<string, AccountSummary[]> = {};
	let latestUpdate = 0;
	let currencySettings: CurrencySettings = defaultCurrencySettings();
	let fxQuote: FxQuote = identityFxQuote(currencySettings);
	let fetchInFlight: Promise<void> | null = null;
	let countdownId: ReturnType<typeof setInterval> | null = null;
	let amountEl: HTMLParagraphElement | null = null;
	let countdownSeconds = 0;
	let lastCountdown = 0;
	let fetchedThisCycle = false;
	let lastForcedRefreshAt = 0;
	let resumeLoading = false;
	let refreshing = false;

	$: displayRate = currencySettings.currency === 'USD' ? 1 : fxQuote.rate;
	$: displayCurrency = currencySettings.currency;
	$: shown = formatAmount(adjusted, displayRate);
	$: amountParts = splitAmount(shown);
	$: tone = Math.abs(adjusted) < 0.005 ? 'flat' : adjusted >= 0 ? 'plus' : 'minus';
	$: percent = initialCapital > 0 ? (adjusted / initialCapital) * 100 : 0;
	$: percentShown = formatPlain(percent);
	$: percentTone = Math.abs(percent) < 0.005 ? 'flat' : percent >= 0 ? 'plus' : 'minus';
	$: delta = snapshotDelta ?? 0;
	$: deltaShown = formatAmount(delta, displayRate);
	$: deltaTone = Math.abs(delta) < 0.005 ? 'flat' : delta >= 0 ? 'plus' : 'minus';
	$: displayPairs = listDisplayPairs(unitGroups);
	$: signedPairs = splitSignedPairs(displayPairs);
	$: positivePairs = signedPairs.positive;
	$: negativePairs = signedPairs.negative;
	$: stamp = latestUpdate > 0 ? formatDateTime(latestUpdate) : '';
	$: stale = latestUpdate > 0 && Date.now() - latestUpdate >= 5 * 60 * 1000;
	$: countLabel = String(countdownSeconds).padStart(2, '0');
	$: statusLabel = failed ? 'Unable to load P/L' : loading && !hasValue ? 'Loading P/L' : 'Adjusted P/L';

	function formatAmount(amount: number, rate: number): string {
		return formatPlain(convertUsd(amount, rate));
	}

	function formatPlain(value: number): string {
		const result = new Intl.NumberFormat('th-TH', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		}).format(Math.abs(value));
		return result === '-0.00' ? '0.00' : result;
	}

	function formatDateTime(ms: number): string {
		const d = new Date(ms);
		const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);
		return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}`;
	}

	function latestFromSummaries(summaries: Array<{ last_update?: string }> | undefined): number {
		return (summaries || []).reduce((latest, account) => {
			const t = new Date(account.last_update || '').getTime();
			return Number.isFinite(t) && t > latest ? t : latest;
		}, 0);
	}

	function splitAmount(formatted: string): { whole: string; frac: string } {
		const index = formatted.lastIndexOf('.');
		if (index === -1) return { whole: formatted, frac: '' };
		return { whole: formatted.slice(0, index), frac: formatted.slice(index) };
	}

	function readCache(): WatchPayload | null {
		try {
			const raw = sessionStorage.getItem(CACHE_KEY);
			return raw ? (JSON.parse(raw) as WatchPayload) : null;
		} catch {
			return null;
		}
	}

	function writeCache(payload: WatchPayload) {
		try {
			sessionStorage.setItem(CACHE_KEY, JSON.stringify(payload));
		} catch {
			/* ignore */
		}
	}

	function fitAmount() {
		if (!amountEl) return;
		const budget = amountEl.clientWidth;
		if (budget <= 0) return;
		let size = Math.min(50, budget * 0.3);
		amountEl.style.fontSize = `${size}px`;
		while (amountEl.scrollWidth > budget && size > 16) {
			size -= 0.5;
			amountEl.style.fontSize = `${size}px`;
		}
	}

	function applyPayload(payload: WatchPayload) {
		currencySettings = payload.currency
			? normalizeCurrencySettings(payload.currency)
			: defaultCurrencySettings();
		if (payload.fx && typeof payload.fx.rate === 'number' && payload.fx.rate > 0) {
			fxQuote = {
				...identityFxQuote(currencySettings),
				...payload.fx
			};
		} else {
			fxQuote = identityFxQuote(currencySettings);
		}
		adjusted = computeAdjustedProfitLoss(
			payload.stats?.profit_loss || 0,
			payload.accountWithdrawals || {},
			payload.accountDeposits || {}
		);
		initialCapital =
			typeof payload.stats?.initial_capital === 'number' ? payload.stats.initial_capital : 0;
		snapshot = payload.snapshot || null;
		snapshotDelta = payload.snapshotDelta ?? null;
		unitGroups = payload.unitGroups || {};
		latestUpdate = latestFromSummaries(payload.summaries);
		hasValue = true;
		failed = false;
		loading = false;
		writeCache(payload);
	}

	if (data.initial) {
		applyPayload(data.initial);
	} else {
		const cached = typeof sessionStorage !== 'undefined' ? readCache() : null;
		if (cached) applyPayload(cached);
	}

	async function fetchData() {
		if (fetchInFlight) return fetchInFlight;

		const run = async () => {
			if (hasValue) refreshing = true;
			try {
				const response = await fetch(`/api/data?t=${Date.now()}`, { cache: 'no-store' });
				if (!response.ok) throw new Error('bad status');
				const payload = (await response.json()) as WatchPayload & { error?: string };
				if (payload.error) throw new Error(payload.error);
				applyPayload(payload);
			} catch {
				failed = !hasValue;
				loading = false;
			} finally {
				refreshing = false;
			}
		};

		fetchInFlight = run().finally(() => {
			fetchInFlight = null;
		});
		return fetchInFlight;
	}

	async function takeSnapshot() {
		if (snapshotLoading) return;
		snapshotLoading = true;
		try {
			const res = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ snapshot: { value: adjusted, kind: 'adjusted' } })
			});
			if (res.ok) await fetchData();
		} finally {
			snapshotLoading = false;
		}
	}

	async function clearSnapshot() {
		if (snapshotLoading) return;
		snapshotLoading = true;
		try {
			const res = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ clear_snapshot: true })
			});
			if (res.ok) {
				snapshot = null;
				snapshotDelta = null;
				await fetchData();
			}
		} finally {
			snapshotLoading = false;
		}
	}

	function stopCountdown() {
		if (countdownId) {
			clearInterval(countdownId);
			countdownId = null;
		}
	}

	function startCountdown() {
		if (countdownId) return;
		updateCountdown();
		countdownId = setInterval(updateCountdown, 1000);
	}

	function updateCountdown() {
		const now = new Date();
		const sec = now.getSeconds();
		countdownSeconds = (10 - (sec % 10)) % 10;
		const cycleStart = countdownSeconds > lastCountdown;
		if (cycleStart) fetchedThisCycle = false;
		if (!resumeLoading && countdownSeconds === 0 && !fetchedThisCycle) {
			fetchedThisCycle = true;
			void fetchData();
		}
		const nowMs = now.getTime();
		const dataStale = latestUpdate > 0 && nowMs - latestUpdate > STALE_FORCE_REFRESH_MS;
		if (!resumeLoading && dataStale && nowMs - lastForcedRefreshAt > 5000) {
			lastForcedRefreshAt = nowMs;
			fetchedThisCycle = true;
			void fetchData();
		}
		lastCountdown = countdownSeconds;
	}

	async function fetchLatestOnResume() {
		if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
		if (resumeLoading) return;
		resumeLoading = true;
		fetchedThisCycle = true;
		try {
			await fetchData();
		} finally {
			resumeLoading = false;
			startCountdown();
			fitAmount();
		}
	}

	function handleVisibility() {
		if (document.visibilityState === 'visible') void fetchLatestOnResume();
	}

	function handlePageShow(event: PageTransitionEvent) {
		if (event.persisted) void fetchLatestOnResume();
	}

	onMount(() => {
		document.documentElement.classList.add('watch-glance');
		void fetchData();
		startCountdown();
		document.addEventListener('visibilitychange', handleVisibility);
		window.addEventListener('pageshow', handlePageShow);
		window.addEventListener('resize', fitAmount);
		requestAnimationFrame(fitAmount);

		return () => {
			document.documentElement.classList.remove('watch-glance');
			document.removeEventListener('visibilitychange', handleVisibility);
			window.removeEventListener('pageshow', handlePageShow);
			window.removeEventListener('resize', fitAmount);
			stopCountdown();
		};
	});

	onDestroy(() => {
		stopCountdown();
	});
</script>

<svelte:head>
	<title>Profit Monitor for Watch</title>
</svelte:head>

<main class="watch" aria-live="polite" aria-label={statusLabel}>
	{#if loading && !hasValue}
		<p class="amount flat">···</p>
	{:else if failed}
		<p class="amount flat">—</p>
	{:else}
		<div class="hero">
			<p class="amount {tone}" bind:this={amountEl}>
				<span class="flag">
					<CurrencyFlag currency={displayCurrency} size={28} />
				</span>
				<span class="num">
					<span class="int">{amountParts.whole}</span><span class="frac">{amountParts.frac}</span>
				</span>
			</p>
			<p class="meta {percentTone}">{percentShown}%</p>
			{#if displayPairs.length > 0}
				<div class="bubbles" aria-label="Pair diffs">
					{#each positivePairs as p, i (`p-${p.unit}-${p.pairMagic ?? 'x'}-${p.buyAccount}-${i}`)}
						<span class="chip fac-chip-plus">+{Math.round(p.diffPoints)}</span>
					{/each}
					{#each negativePairs as p, i (`n-${p.unit}-${p.pairMagic ?? 'x'}-${p.sellAccount}-${i}`)}
						<span class="chip fac-chip-minus">{Math.round(p.diffPoints)}</span>
					{/each}
				</div>
			{/if}
			<div class="fresh">
				{#if stamp}
					<p class="meta stamp" class:stale class:busy={refreshing}>{stamp}</p>
				{/if}
				<p class="count">{countLabel}</p>
			</div>
			{#if snapshot}
				<p class="meta {deltaTone}">Δ {deltaShown}</p>
			{/if}
			<div class="actions">
				<button type="button" on:click={takeSnapshot} disabled={snapshotLoading}>SNAPSHOT</button>
				{#if snapshot}
					<button type="button" on:click={clearSnapshot} disabled={snapshotLoading}>CLEAR</button>
				{/if}
			</div>
		</div>
	{/if}
</main>

<style>
	:global(html.watch-glance),
	:global(html.watch-glance body) {
		margin: 0;
		height: 100%;
		background: #0a0a0a;
	}

	.watch {
		min-height: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		padding: 8px max(16px, env(safe-area-inset-right)) 12px max(16px, env(safe-area-inset-left));
		box-sizing: border-box;
	}

	.hero {
		--ui: 1.45;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: calc(6px * var(--ui));
		width: 100%;
		max-width: 100%;
	}

	.amount {
		display: flex;
		align-items: center;
		justify-content: center;
		margin: 0;
		width: 100%;
		max-width: 100%;
		font-family: 'Barlow Condensed', 'Azeret Mono', sans-serif;
		font-weight: 800;
		font-size: clamp(1.95rem, 22vw, 3.5rem);
		letter-spacing: -0.03em;
		line-height: 0.9;
		text-align: center;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
		gap: 0.16em;
		box-sizing: border-box;
	}

	.num {
		display: inline-flex;
		align-items: baseline;
		min-width: 0;
	}

	.frac {
		font-size: 0.38em;
		font-weight: 600;
		letter-spacing: 0;
		opacity: 0.62;
	}

	.flag {
		display: inline-flex;
		align-items: center;
		flex-shrink: 0;
		width: 0.42em;
		height: 0.3em;
	}

	.flag :global(span) {
		width: 100% !important;
		height: 100% !important;
	}

	.flag :global(svg) {
		display: block;
		width: 100%;
		height: 100%;
	}

	.meta {
		margin: 0;
		font-family: 'Azeret Mono', ui-monospace, monospace;
		font-size: calc(11px * var(--ui));
		letter-spacing: -0.02em;
		line-height: 1.2;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.bubbles {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		align-items: center;
		gap: calc(4px * var(--ui));
		width: 100%;
		font-family: 'Azeret Mono', ui-monospace, monospace;
		font-size: calc(11px * var(--ui));
		letter-spacing: -0.02em;
		line-height: 1.2;
		font-variant-numeric: tabular-nums;
	}

	.chip {
		padding: calc(2px * var(--ui)) calc(6px * var(--ui));
		border-radius: 6px;
		font-weight: 600;
	}

	.actions {
		display: flex;
		gap: calc(6px * var(--ui));
		margin-top: calc(2px * var(--ui));
	}

	.actions button {
		background: transparent;
		color: #f5f5f5;
		border: 1px solid #f5f5f5;
		min-height: calc(28px * var(--ui));
		padding: calc(4px * var(--ui)) calc(8px * var(--ui));
		font: inherit;
		font-size: calc(10px * var(--ui));
		letter-spacing: 0.04em;
	}

	.actions button:disabled {
		opacity: 0.45;
	}

	.actions button:focus-visible {
		outline: 2px solid #f5f5f5;
		outline-offset: 2px;
	}

	.plus {
		color: #3dff6a;
	}

	.minus {
		color: #ff4d4d;
	}

	.flat {
		color: #ececec;
	}

	.fresh {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: calc(8px * var(--ui));
		width: 100%;
	}

	.stamp {
		color: #ececec;
		font-size: calc(10px * var(--ui));
	}

	.stamp.stale {
		color: #ffcc33;
	}

	.count {
		flex-shrink: 0;
		margin: 0;
		min-width: 1.7em;
		padding: calc(2px * var(--ui)) calc(5px * var(--ui));
		border: 1px solid #f5f5f5;
		color: #f5f5f5;
		font-family: 'Azeret Mono', ui-monospace, monospace;
		font-size: calc(10px * var(--ui));
		line-height: 1.2;
		text-align: center;
		font-variant-numeric: tabular-nums;
	}

	.stamp.busy {
		opacity: 0.4;
	}

	@media (hover: hover) {
		.stamp.busy {
			animation: pulse 0.85s ease-out infinite;
			opacity: 1;
		}
	}

	@keyframes pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.28;
		}
	}
</style>
