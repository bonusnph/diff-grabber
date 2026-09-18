<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { AccountSummary, CurrencySettings, DashboardStats, FxQuote, OrderInfo, PlAlertSettings, PlAlertState } from '$lib/types.js';
	import { defaultPlAlertSettings, defaultPlAlertState } from '$lib/pl-alert-model.js';
	import { convertUsd, defaultCurrencySettings, identityFxQuote, normalizeCurrencySettings } from '$lib/currency.js';
	import CurrencyFlag from '$lib/CurrencyFlag.svelte';

	interface PairInfo {
		symbol: string;
		/** Raw symbols from BUY / SELL legs (pair label is derived, sorted A–Z). */
		buySymbol?: string;
		sellSymbol?: string;
		buyAccount: string;
		sellAccount: string;
		buyBroker: string;
		sellBroker: string;
		buyPrice: number;
		sellPrice: number;
		diff: number;
		diffPoints: number;
		lots: number;
		buyLots: number;
		sellLots: number;
		openTime: string;
		/** BUY leg open time (ISO); pair rows only. */
		buyOpenTime?: string;
		/** SELL leg open time (ISO); pair rows only. */
		sellOpenTime?: string;
		pairMagic?: number;
	}

	type UnitPair = PairInfo & { unit: number };

	function nearlyEqualAtTick(price: number, roundedToTick: number): boolean {
		return Math.abs(price - roundedToTick) <= 1e-9 * Math.max(1, Math.abs(price));
	}

	/** Smallest fractional digit count that represents this quote on a uniform grid. */
	function inferFractionDecimalsForPrice(p: number): number {
		for (let d = 0; d <= 12; d++) {
			const scale = Math.pow(10, d);
			const r = Math.round(p * scale) / scale;
			if (nearlyEqualAtTick(r, p)) return d;
		}
		return 5;
	}

	/**
	 * Align BUY and SELL to the coarser implied precision (min decimals per leg), scale to integers, subtract.
	 * Example: buy 4500.12 (2 dp), sell 4600.120 (3 dp) → scale ×100 → 450012 vs 460012 → diff 10000 ticks at 0.01.
	 */
	function spreadDiffWholeTicks(buyPrice: number, sellPrice: number): number {
		const db = inferFractionDecimalsForPrice(buyPrice);
		const ds = inferFractionDecimalsForPrice(sellPrice);
		const d = Math.min(db, ds);
		const scale = Math.pow(10, d);
		return Math.round(sellPrice * scale) - Math.round(buyPrice * scale);
	}

	/** Both leg symbols, sorted alphabetically, as "A - B" (for cross-broker suffixes). */
	function formatPairSymbolsLabel(buySym: string | undefined, sellSym: string | undefined): string {
		const bs = (buySym ?? '').trim();
		const ss = (sellSym ?? '').trim();
		if (!bs && !ss) return '';
		if (!bs) return ss;
		if (!ss) return bs;
		const [a, b] = [bs, ss].sort((x, y) => x.localeCompare(y));
		return `${a} - ${b}`;
	}

	function computeUnitPairs(accounts: AccountSummary[]): { pairs: PairInfo[]; unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> } {
		type Annotated = OrderInfo & { account_number: string; broker_name: string; openMs: number };

		function annotate(acc: AccountSummary, o: OrderInfo): Annotated | null {
			if (!o?.openTime) return null;
			const ms = new Date(o.openTime).getTime();
			if (!isFinite(ms)) return null;
			return {
				...o,
				account_number: acc.account_number,
				broker_name: acc.broker_name,
				openMs: ms
			};
		}

		function orderMagic(o: OrderInfo): number | undefined {
			if (typeof o.magic !== 'number' || !Number.isFinite(o.magic)) return undefined;
			return o.magic;
		}

		function makePair(buy: Annotated, sell: Annotated, magic?: number): PairInfo {
			const diff = sell.price - buy.price;
			const bs = (buy.symbol || '').trim();
			const ss = (sell.symbol || '').trim();
			const pi: PairInfo = {
				symbol: formatPairSymbolsLabel(bs, ss) || bs || ss,
				buySymbol: bs,
				sellSymbol: ss,
				buyAccount: buy.account_number,
				sellAccount: sell.account_number,
				buyBroker: buy.broker_name,
				sellBroker: sell.broker_name,
				buyPrice: buy.price,
				sellPrice: sell.price,
				diff,
				diffPoints: spreadDiffWholeTicks(buy.price, sell.price),
				lots: (buy.lots + sell.lots) / 2,
				buyLots: buy.lots,
				sellLots: sell.lots,
				openTime: new Date(Math.min(buy.openMs, sell.openMs)).toISOString(),
				buyOpenTime: new Date(buy.openMs).toISOString(),
				sellOpenTime: new Date(sell.openMs).toISOString()
			};
			if (magic !== undefined) pi.pairMagic = magic;
			return pi;
		}

		const allBuys: Annotated[] = [];
		const allSells: Annotated[] = [];
		for (const acc of accounts || []) {
			const orders = (acc.orders || []) as OrderInfo[];
			for (const o of orders) {
				const a = annotate(acc, o);
				if (!a) continue;
				if (o.side === 'BUY') allBuys.push(a);
				else if (o.side === 'SELL') allSells.push(a);
			}
		}

		const pairs: PairInfo[] = [];
		const buysMagic = new Map<number, Annotated[]>();
		const sellsMagic = new Map<number, Annotated[]>();
		const unpairedBuys: Annotated[] = [];
		const unpairedSells: Annotated[] = [];

		for (const buy of allBuys) {
			const m = orderMagic(buy);
			if (m !== undefined) {
				const arr = buysMagic.get(m) ?? [];
				arr.push(buy);
				buysMagic.set(m, arr);
			} else {
				unpairedBuys.push(buy);
			}
		}
		for (const sell of allSells) {
			const m = orderMagic(sell);
			if (m !== undefined) {
				const arr = sellsMagic.get(m) ?? [];
				arr.push(sell);
				sellsMagic.set(m, arr);
			} else {
				unpairedSells.push(sell);
			}
		}

		const magicKeys = new Set<number>([...buysMagic.keys(), ...sellsMagic.keys()]);
		for (const mk of magicKeys) {
			const bList = [...(buysMagic.get(mk) ?? [])].sort((x, y) => x.openMs - y.openMs);
			const sList = [...(sellsMagic.get(mk) ?? [])].sort((x, y) => x.openMs - y.openMs);
			const n = Math.min(bList.length, sList.length);
			for (let i = 0; i < n; i++) {
				pairs.push(makePair(bList[i], sList[i], mk));
			}
			for (let i = n; i < bList.length; i++) unpairedBuys.push(bList[i]);
			for (let i = n; i < sList.length; i++) unpairedSells.push(sList[i]);
		}

		unpairedBuys.sort((a, b) => a.openMs - b.openMs);
		unpairedSells.sort((a, b) => a.openMs - b.openMs);

		const unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> = [];
		for (const leg of unpairedBuys) {
			const { openMs: _omitMs, ...rest } = leg;
			unmatched.push(rest);
		}
		for (const leg of unpairedSells) {
			const { openMs: _omitMs, ...rest } = leg;
			unmatched.push(rest);
		}

		const magicAscKey = (m: number | undefined) =>
			typeof m === 'number' && Number.isFinite(m) ? m : Number.POSITIVE_INFINITY;
		pairs.sort((a, b) => magicAscKey(a.pairMagic) - magicAscKey(b.pairMagic));
		unmatched.sort((a, b) => magicAscKey(orderMagic(a)) - magicAscKey(orderMagic(b)));

		return { pairs, unmatched };
	}

	let stats: DashboardStats = {
		total_balance: 0,
		profit_loss: 0,
		initial_capital: 60000,
		account_count: 0
	};
	let summaries: AccountSummary[] = [];
    let initialCapital = 64000;
    let unitInitialCapitals: Record<number, number> = {};
	// totalActiveAccounts now calculated from number of units * 2
    let unitWarningEquityPercentages: Record<number, number> = {};
    let unitMappings: Record<number, string> = {};
	let unitBrokerMinMargins: Record<number, Record<string, number>> = {};
	let unitGroups: Record<string, AccountSummary[]> = {};
	let unitStats: Array<{
		unit: number;
		totalBalance: number;
		profitLoss: number;
		accountCount: number;
	}> = [];
	let unitWithdrawals: Record<number, number> = {};
	let accountWithdrawals: Record<string, number> = {};
	let accountDeposits: Record<string, number> = {};
	let loading = true;
	let pollingInterval = 5; // seconds
	let intervalId: ReturnType<typeof setInterval> | null = null;
	let countdownSeconds = 0;
	let countdownInterval: ReturnType<typeof setInterval> | null = null;
	let autoFetchEnabled = false;
	let fetchedThisCycle = false;
	let lastCountdown = 0;
	const STALE_FORCE_REFRESH_MS = 30 * 1000;
	let lastForcedRefreshAt = 0;
	let showSettingsModal = false;
	let plAlertSettings: PlAlertSettings = defaultPlAlertSettings();
	let plAlertState: PlAlertState = defaultPlAlertState();
	let draftPlAlert: PlAlertSettings = defaultPlAlertSettings();
	let currencySettings: CurrencySettings = defaultCurrencySettings();
	let draftCurrency: CurrencySettings = defaultCurrencySettings();
	let fxQuote: FxQuote = identityFxQuote(defaultCurrencySettings());
	let resettingAlert: 'profit' | 'loss' | null = null;
	const REVEAL_BOOK_KEY = 'pm-reveal-book';
	function readStoredRevealBook(): boolean {
		try {
			return sessionStorage.getItem(REVEAL_BOOK_KEY) !== '0';
		} catch {
			return true;
		}
	}
	let revealBookValues = typeof sessionStorage !== 'undefined' ? readStoredRevealBook() : true;
	function setRevealBookValues(next: boolean) {
		revealBookValues = next;
		try {
			sessionStorage.setItem(REVEAL_BOOK_KEY, next ? '1' : '0');
		} catch {
			/* ignore */
		}
	}
	let savingSettings = false;
    let snapshotLoading = false;
	let latestUpdate: number = 0;
	let settingsLoaded = false;
	let appReady = false;

	// Delete data confirmation
	let showDeleteConfirmModal = false;
	let deletingData = false;

	let profitLossPercent = 0;
	let isRefreshing = false;
	let resumeLoading = false;
	// Filters (Broker / Account Name)
	let activeBrokers: Set<string> = new Set();
	let activeAccountNames: Set<string> = new Set();
	let filtersInitialized = false;
	let showFilters = false;

	// Unit visibility state (default all expanded)
	let unitVisibility: Record<number, boolean> = {};

	// Broker detail expansion in sum total (level 1: broker, level 2: broker::name)
	let expandedBrokers: Set<string> = new Set();
	let expandedBrokerNames: Set<string> = new Set();

	// Pause auto fetch when settings modal is open
	$: (() => {
		if (showSettingsModal) {
			autoFetchEnabled = false;
		} else {
			autoFetchEnabled = true;
		}
	})();

	$: appReady = settingsLoaded;
	$: displayRate = currencySettings.currency === 'USD' ? 1 : fxQuote.rate;
	$: displayCurrency = currencySettings.currency;

	$: uniqueBrokersList = (() => {
		const counts = new Map<string, number>();
		for (const a of summaries || []) {
			const key = a.broker_name || '';
			counts.set(key, (counts.get(key) || 0) + 1);
		}
		return Array.from(counts.entries())
			.sort((x, y) => x[0].localeCompare(y[0]))
			.map(([name, count]) => ({ name, count }));
	})();

	$: uniqueAccountNamesList = (() => {
		const counts = new Map<string, number>();
		for (const a of summaries || []) {
			const key = a.account_name || '';
			counts.set(key, (counts.get(key) || 0) + 1);
		}
		return Array.from(counts.entries())
			.sort((x, y) => x[0].localeCompare(y[0]))
			.map(([name, count]) => ({ name, count }));
	})();

	$: (() => {
		if (!filtersInitialized && (uniqueBrokersList?.length || uniqueAccountNamesList?.length)) {
			activeBrokers = new Set((uniqueBrokersList || []).map((x) => x.name));
			activeAccountNames = new Set((uniqueAccountNamesList || []).map((x) => x.name));
			filtersInitialized = true;
		}
	})();

	function toggleBroker(name: string) {
		const next = new Set(activeBrokers);
		if (next.has(name)) next.delete(name);
		else next.add(name);
		activeBrokers = next;
	}

	function toggleAccountName(name: string) {
		const next = new Set(activeAccountNames);
		if (next.has(name)) next.delete(name);
		else next.add(name);
		activeAccountNames = next;
	}

	function selectAllBrokers() {
		activeBrokers = new Set((uniqueBrokersList || []).map((x) => x.name));
	}

	function clearAllBrokers() {
		activeBrokers = new Set();
	}

	function selectAllAccountNames() {
		activeAccountNames = new Set((uniqueAccountNamesList || []).map((x) => x.name));
	}

	function clearAllAccountNames() {
		activeAccountNames = new Set();
	}

	function toggleUnitVisibility(unit: number) {
		const newValue = !isUnitVisible(unit);
		unitVisibility = { ...unitVisibility, [unit]: newValue };
	}

	function isUnitVisible(unit: number): boolean {
		// Default to true (expanded) if undefined, otherwise use the stored value
		return unitVisibility[unit] !== false;
	}

	function collapseAllUnits() {
		const newVisibility: Record<number, boolean> = {};
		Object.keys(unitGroups || {}).forEach(unitStr => {
			const unit = parseInt(unitStr);
			newVisibility[unit] = false;
		});
		unitVisibility = { ...unitVisibility, ...newVisibility };
	}

	function expandAllUnits() {
		const newVisibility: Record<number, boolean> = {};
		Object.keys(unitGroups || {}).forEach(unitStr => {
			const unit = parseInt(unitStr);
			newVisibility[unit] = true;
		});
		unitVisibility = { ...unitVisibility, ...newVisibility };
	}

	// Default collapsed: ensure any unit without an explicit state starts as collapsed
	$: (() => {
		const keys = Object.keys(unitGroups || {});
		if (!keys.length) return;
		let shouldUpdate = false;
		const next: Record<number, boolean> = { ...unitVisibility };
		for (const unitStr of keys) {
			const unit = parseInt(unitStr);
			if (next[unit] === undefined) {
				next[unit] = false;
				shouldUpdate = true;
			}
		}
		if (shouldUpdate) unitVisibility = next;
	})();


	let newUnitBrokerUnit = '';
	let newUnitBrokerName = '';
	let newUnitBrokerMargin = '';
	let draftCapitals: Record<number, number> = {};
	let draftWarns: Record<number, number> = {};
	let draftMappings: Record<number, string> = {};
	let draftBrokerMargins: Record<number, Record<string, number>> = {};
	let draftWithdrawals: Record<string, number> = {};
	let draftDeposits: Record<string, number> = {};

	// Dynamic Unit Settings editing (Initial Capital & Warn %)
	let newUnitSettingNumber: string = '';
	let newUnitSettingName: string = '';
	let newUnitSettingCap: string = '';
	let newUnitSettingWarn: string = '';

	function cloneJson<T>(value: T): T {
		return JSON.parse(JSON.stringify(value ?? {}));
	}

	function openSettings() {
		draftCapitals = { ...unitInitialCapitals };
		draftWarns = { ...unitWarningEquityPercentages };
		draftMappings = { ...unitMappings };
		draftBrokerMargins = cloneJson(unitBrokerMinMargins || {});
		draftWithdrawals = { ...accountWithdrawals };
		draftDeposits = { ...accountDeposits };
		draftPlAlert = { ...plAlertSettings };
		draftCurrency = { ...currencySettings };
		showSettingsModal = true;
	}

	function closeSettings() {
		showSettingsModal = false;
	}

    function addUnitSetting() {
		const unit = parseInt(newUnitSettingNumber);
		if (isNaN(unit) || unit < 1) return;
		const capParsed = parseFloat(newUnitSettingCap);
		const warnParsed = parseFloat(newUnitSettingWarn);
		const cap = isNaN(capParsed) || capParsed < 0 ? 0 : capParsed;
		const warn = isNaN(warnParsed) || warnParsed < 1 || warnParsed > 100 ? 30 : warnParsed;
		draftCapitals = { ...draftCapitals, [unit]: cap };
		draftWarns = { ...draftWarns, [unit]: warn };
		draftMappings = { ...draftMappings, [unit]: newUnitSettingName.trim() };
		newUnitSettingNumber = '';
		newUnitSettingName = '';
		newUnitSettingCap = '';
		newUnitSettingWarn = '';
	}

	function removeUnitSetting(unit: number) {
		const nextCap = { ...draftCapitals };
		delete nextCap[unit];
		draftCapitals = nextCap;
		const nextWarn = { ...draftWarns };
		delete nextWarn[unit];
		draftWarns = nextWarn;
		const nextMap = { ...draftMappings };
		delete nextMap[unit];
		draftMappings = nextMap;
	}

	$: settingsUnitList = Array.from(new Set([
		...Object.keys(draftMappings || {}),
		...Object.keys(draftCapitals || {}),
		...Object.keys(draftWarns || {})
	])).map((k) => parseInt(k as any)).filter((n) => !isNaN(n)).sort((a, b) => a - b);

	$: unitList = Array.from(new Set([
		...Object.keys(unitMappings || {}),
		...Object.keys(unitInitialCapitals || {}),
		...Object.keys(unitWarningEquityPercentages || {})
	])).map((k) => parseInt(k as any)).filter((n) => !isNaN(n)).sort((a, b) => a - b);

	// Data completeness check - calculate totalActiveAccounts from number of units * 2
	$: totalActiveAccounts = Object.keys(unitGroups || {}).length * 2;
	$: currentActiveAccounts = summaries.length;
	$: isDataComplete = currentActiveAccounts >= totalActiveAccounts;
	$: dataCompletenessPercentage =
		totalActiveAccounts > 0 ? Math.round((currentActiveAccounts / totalActiveAccounts) * 100) : 0;

	// Group summaries by broker
	$: groupedSummaries = summaries.reduce(
		(groups, summary) => {
			const broker = summary.broker_name;
			if (!groups[broker]) {
				groups[broker] = [];
			}
			groups[broker].push(summary);
			return groups;
		},
		{} as Record<string, AccountSummary[]>
	);

	function unitHasOpenTrades(pairs: PairInfo[], unmatched: Array<OrderInfo & { account_number: string; broker_name: string }>): boolean {
		return pairs.length > 0 || unmatched.length > 0;
	}

    $: profitLossPercent = initialCapital > 0 ? (stats.profit_loss / initialCapital) * 100 : 0;
	$: totalWaitingWD = Object.values(accountWithdrawals || {}).reduce(
		(sum, v) => sum + (typeof v === 'number' ? v : 0),
		0
	);

	$: totalDeposits = Object.values(accountDeposits || {}).reduce(
		(sum, v) => sum + (typeof v === 'number' ? v : 0),
		0
	);
	$: adjustedProfitLoss = (stats?.profit_loss || 0) + (totalWaitingWD || 0) - (totalDeposits || 0);
	$: adjustedProfitLossPercent =
		initialCapital > 0 ? (adjustedProfitLoss / initialCapital) * 100 : 0;

	// Snapshot data returned from server
	let snapshot: { value: number; kind: 'adjusted' | 'real'; timestamp: string } | null = null;
	let snapshotDelta: number | null = null;

	let unitPairsMap: Record<number, { pairs: PairInfo[]; unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> }> = {};
	let allPairs: UnitPair[] = [];
	let legacyUnitPairs: UnitPair[] = [];
	let displayPairs: UnitPair[] = [];
	let positivePairs: UnitPair[] = [];
	let negativePairs: UnitPair[] = [];
	let positivePairsCount = 0;
	let negativePairsCount = 0;
	let tradingPairs = 0;

	$: unitPairsMap = Object.entries(unitGroups || {}).reduce(
		(acc, [unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			acc[unit] = computeUnitPairs(accounts);
			return acc;
		},
		{} as Record<number, { pairs: PairInfo[]; unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> }>
	);

	$: allPairs = Object.entries(unitPairsMap).flatMap(([unitStr, value]) => {
		const unit = parseInt(unitStr);
		return (value?.pairs || []).map((p) => ({ ...p, unit }));
	});

	$: legacyUnitPairs = Object.entries(unitGroups || {}).flatMap(([unitStr, accounts]) => {
		const unit = parseInt(unitStr);
		const ud = unitPairsMap[unit];
		if (!ud || ud.pairs.length > 0 || ud.unmatched.length > 0) return [];
		const lp = computeLegacyUnitPair(unit, accounts);
		return lp ? [lp] : [];
	});

	$: displayPairs = [...allPairs, ...legacyUnitPairs];

	$: positivePairs = displayPairs
		.filter((p) => p.diffPoints >= 0)
		.sort((a, b) => b.diffPoints - a.diffPoints);
	$: negativePairs = displayPairs
		.filter((p) => p.diffPoints < 0)
		.sort((a, b) => b.diffPoints - a.diffPoints);
	$: positivePairsCount = positivePairs.length;
	$: negativePairsCount = negativePairs.length;
	$: tradingPairs = displayPairs.length;

	// Count accounts with low equity warning
	$: lowEquityWarningAccounts = summaries.filter(isLowEquityWarning);
	$: lowEquityWarningCount = lowEquityWarningAccounts.length;
	$: lowEquityUnits = [...new Set(lowEquityWarningAccounts.map(a => a.unit))].sort((a, b) => a - b);

	// Function to check if unit has stale data
	function hasUnitStaleData(accounts: AccountSummary[]): boolean {
		return accounts.some(account => getDataAge(account.last_update).status === 'stale');
	}

	let fetchInFlight: Promise<void> | null = null;

	async function fetchData() {
		if (!loading) isRefreshing = true;
		if (fetchInFlight) return fetchInFlight;

		const run = async () => {
			const showRefreshing = !loading;
			if (showRefreshing) {
				isRefreshing = true;
			}
			try {
				const response = await fetch(`/api/data?t=${Date.now()}`, {
					cache: 'no-store'
				});
				const data = await response.json();

				stats = data.stats;
				summaries = data.summaries;
				unitGroups = data.unitGroups || {};
				unitStats = data.unitStats || [];
				accountWithdrawals = data.accountWithdrawals || {};
				accountDeposits = data.accountDeposits || {};
				latestUpdate = (summaries || []).reduce((latest, a) => {
					const t = new Date(a.last_update).getTime();
					return t > latest ? t : latest;
				}, 0);
				snapshot = data.snapshot || null;
				snapshotDelta = data.snapshotDelta ?? null;
				if (data.plAlert?.settings) plAlertSettings = data.plAlert.settings;
				if (data.plAlert?.state) plAlertState = data.plAlert.state;
				applyCurrencyPayload(data);
				loading = false;
			} catch (error) {
				console.error('Error fetching data:', error);
				loading = false;
			} finally {
				if (showRefreshing) {
					isRefreshing = false;
				}
			}
		};

		fetchInFlight = run().finally(() => {
			fetchInFlight = null;
		});
		return fetchInFlight;
	}

	/** Immediate fetch when the tab/app becomes visible again (mobile browsers freeze timers). */
	async function fetchLatestOnResume() {
		if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
		if (resumeLoading) return;
		resumeLoading = true;
		isRefreshing = true;
		fetchedThisCycle = true;
		try {
			await fetchData();
		} finally {
			resumeLoading = false;
			updateCountdown();
		}
	}

	function handleVisibilityChange() {
		if (document.visibilityState === 'visible' && appReady) {
			void fetchLatestOnResume();
		}
	}

	function handlePageShow(event: PageTransitionEvent) {
		if (!appReady) return;
		if (event.persisted || document.visibilityState === 'visible') {
			void fetchLatestOnResume();
		}
	}

	async function takeSnapshot(kind: 'adjusted' | 'real' = 'adjusted') {
		if (snapshotLoading) return;
		snapshotLoading = true;
		try {
			const value = kind === 'adjusted' ? adjustedProfitLoss : stats.profit_loss;
			const res = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ snapshot: { value, kind } })
			});
			if (res.ok) {
				await fetchData();
			}
		} finally {
			snapshotLoading = false;
		}
	}

	async function clearSnapshot() {
		if (snapshotLoading) return;
		snapshotLoading = true;
		try {
			console.log('Sending clear snapshot request...');
			const res = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ clear_snapshot: true })
			});
			
			if (res.ok) {
				const result = await res.json();
				console.log('Clear snapshot response:', result);
				
				snapshot = null;
				snapshotDelta = null;
				
				// Refresh data to ensure snapshot is cleared from server
				console.log('Refreshing data after clear snapshot...');
				await fetchData();
				console.log('Data refreshed. Current snapshot:', snapshot);
			} else {
				const errorData = await res.json();
				console.error('Failed to clear snapshot:', errorData);
			}
		} catch (error) {
			console.error('Error clearing snapshot:', error);
		} finally {
			snapshotLoading = false;
		}
	}

    async function loadInitialCapital() {
		settingsLoaded = false;
		try {
			const response = await fetch('/api/settings');
			const data = await response.json();
            initialCapital = data.initial_capital;
            unitInitialCapitals = data.unit_initial_capitals || {};
			// totalActiveAccounts now calculated automatically from units
            unitWarningEquityPercentages = data.unit_warning_equity_percentages || {};
			unitMappings = data.unit_mappings || {};
			unitBrokerMinMargins = data.unit_broker_min_margins || {};
			unitWithdrawals = data.unit_withdrawals || {};
			accountDeposits = data.account_deposits || {};
			plAlertSettings = data.pl_alert || defaultPlAlertSettings();
			plAlertState = data.pl_alert_state || defaultPlAlertState();
			applyCurrencyPayload({ currency: data.currency, fx: data.fx });
		} catch (error) {
			console.error('Error loading settings:', error);
			// Keep default values if loading fails
		} finally {
			settingsLoaded = true;
		}
	}

	function startPolling() {
		autoFetchEnabled = true;
	}

	function stopPolling() {
		autoFetchEnabled = false;
		if (intervalId) {
			clearInterval(intervalId);
			intervalId = null;
		}
	}

	function updateCountdown() {
		const now = new Date();
		const sec = now.getSeconds();
		countdownSeconds = (10 - (sec % 10)) % 10;
		// Detect new 10s cycle (count jumps up from 0 -> 9)
		const cycleStart = countdownSeconds > lastCountdown;
		if (cycleStart) {
			fetchedThisCycle = false;
		}
		// Trigger fetch one tick after 0 (i.e., when switching to 9)
		if (autoFetchEnabled && !resumeLoading && lastCountdown === 0 && countdownSeconds === 9 && !fetchedThisCycle) {
			fetchedThisCycle = true;
			fetchData();
		}

		// Force refresh if client time is more than 30s newer than last update
		const nowMs = now.getTime();
		const dataStale = latestUpdate > 0 && nowMs - latestUpdate > STALE_FORCE_REFRESH_MS;
		if (autoFetchEnabled && !resumeLoading && dataStale && !isRefreshing && nowMs - lastForcedRefreshAt > 5000) {
			lastForcedRefreshAt = nowMs;
			fetchedThisCycle = true;
			fetchData();
		}
		lastCountdown = countdownSeconds;
	}

	function getDataAge(timestamp: string): {
		minutes: number;
		status: 'fresh' | 'stale';
	} {
		const now = new Date();
		const dataTime = new Date(timestamp);
		const diffMinutes = Math.floor((now.getTime() - dataTime.getTime()) / (1000 * 60));

		if (diffMinutes >= 5) return { minutes: diffMinutes, status: 'stale' };
		return { minutes: diffMinutes, status: 'fresh' };
	}

	async function updateInitialCapital() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ initial_capital: initialCapital })
			});

			if (response.ok) {
				const data = await response.json();
				initialCapital = data.initial_capital; // Update with confirmed value from server
				await fetchData(); // Refresh data to update profit/loss calculation
			}
		} catch (error) {
			console.error('Error updating initial capital:', error);
			// Reload the original value if update fails
			await loadInitialCapital();
		}
	}

    // Removed Capital Per Unit - handled per unit now

	// updateTotalActiveAccounts function removed - now calculated automatically from units

	async function updateUnitMappings() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ unit_mappings: unitMappings })
			});

			if (response.ok) {
				const data = await response.json();
				unitMappings = data.unit_mappings; // Update with confirmed value from server
			}
		} catch (error) {
			console.error('Error updating unit mappings:', error);
			// Reload the original value if update fails
			await loadInitialCapital();
		}
	}


	async function updateUnitBrokerMinMargins() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ unit_broker_min_margins: unitBrokerMinMargins })
			});
			if (response.ok) {
				const data = await response.json();
				unitBrokerMinMargins = data.unit_broker_min_margins || unitBrokerMinMargins;
			}
		} catch (error) {
			console.error('Error updating unit broker min margins:', error);
		}
	}

	async function updateUnitWithdrawals() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ unit_withdrawals: unitWithdrawals })
			});

			if (response.ok) {
				const data = await response.json();
				unitWithdrawals = data.unit_withdrawals || unitWithdrawals;
				// Refresh unitStats and totals to reflect adjustment in backend
				await fetchData();
			}
		} catch (error) {
			console.error('Error updating unit withdrawals:', error);
		}
	}

	function handleWithdrawalChange(unit: number, event: Event) {
		const input = event.target as HTMLInputElement;
		const raw = input.value.trim();
		const parsed = parseFloat(raw);
		const value = !raw ? 0 : isNaN(parsed) || parsed < 0 ? 0 : parsed;
		unitWithdrawals = { ...unitWithdrawals, [unit]: value };
		updateUnitWithdrawals();
	}

	async function updateAccountWithdrawals() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ account_withdrawals: accountWithdrawals })
			});

			if (response.ok) {
				const data = await response.json();
				accountWithdrawals = data.account_withdrawals || accountWithdrawals;
				await fetchData();
			}
		} catch (error) {
			console.error('Error updating account withdrawals:', error);
		}
	}

	async function updateAccountDeposits() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ account_deposits: accountDeposits })
			});

			if (response.ok) {
				const data = await response.json();
				accountDeposits = data.account_deposits || accountDeposits;
				await fetchData();
			}
		} catch (error) {
			console.error('Error updating account deposits:', error);
		}
	}

	function handleAccountWithdrawalChange(accountNumber: string, event: Event) {
		const input = event.target as HTMLInputElement;
		const raw = input.value.trim();
		const parsed = parseFloat(raw);
		const value = !raw ? 0 : isNaN(parsed) || parsed < 0 ? 0 : parsed;
		accountWithdrawals = { ...accountWithdrawals, [accountNumber]: value };
		updateAccountWithdrawals();
	}

	function removeAccountWithdrawal(accountNumber: string) {
		accountWithdrawals = { ...accountWithdrawals, [accountNumber]: 0 };
		updateAccountWithdrawals();
	}

	function handleAccountDepositChange(accountNumber: string, event: Event) {
		const input = event.target as HTMLInputElement;
		const raw = input.value.trim();
		const parsed = parseFloat(raw);
		const value = !raw ? 0 : isNaN(parsed) || parsed < 0 ? 0 : parsed;

		accountDeposits = { ...accountDeposits, [accountNumber]: value };
		updateAccountDeposits();
	}

	function removeAccountDeposit(accountNumber: string) {
		accountDeposits = { ...accountDeposits, [accountNumber]: 0 };
		updateAccountDeposits();
	}

	let adjustingPLUnits: Set<number> = new Set();
	let adjustingAllPL = false;

	async function adjustUnitPLToZero(unit: number) {
		const stat = unitStats.find((s) => s.unit === unit);
		if (!stat || Math.abs(stat.profitLoss) < 0.01) return;

		const accounts = unitGroups[unit] || [];
		if (accounts.length === 0) return;

		const direction = stat.profitLoss > 0 ? 'DP Note' : 'WD Note';
		if (!confirm(`Zero P/L for Unit ${unit}?\n\nP/L: ${formatNumber(stat.profitLoss)}\nWill add ${formatNumber(Math.abs(stat.profitLoss))} to ${direction} of account ${accounts[0].account_number}`)) return;

		adjustingPLUnits = new Set([...adjustingPLUnits, unit]);
		const firstAccount = accounts[0].account_number;
		const pl = Math.round(stat.profitLoss * 100) / 100;

		if (pl > 0) {
			accountDeposits = {
				...accountDeposits,
				[firstAccount]: Math.round(((accountDeposits[firstAccount] ?? 0) + pl) * 100) / 100
			};
			await updateAccountDeposits();
		} else {
			accountWithdrawals = {
				...accountWithdrawals,
				[firstAccount]: Math.round(((accountWithdrawals[firstAccount] ?? 0) + Math.abs(pl)) * 100) / 100
			};
			await updateAccountWithdrawals();
		}

		adjustingPLUnits = new Set([...adjustingPLUnits].filter((u) => u !== unit));
	}

	async function adjustAllGroupsPL() {
		const affectedUnits = unitStats.filter((s) => Math.abs(s.profitLoss) >= 0.01);
		if (affectedUnits.length === 0) return;

		const summary = affectedUnits.map((s) => `  Unit ${s.unit}: P/L ${s.profitLoss >= 0 ? '+' : ''}${formatNumber(s.profitLoss)}`).join('\n');
		if (!confirm(`Zero P/L for all groups?\n\n${summary}\n\nThis will adjust WD/DP Notes for ${affectedUnits.length} group(s).`)) return;

		adjustingAllPL = true;
		const wdUpdates: Record<string, number> = {};
		const dpUpdates: Record<string, number> = {};

		for (const stat of unitStats) {
			if (Math.abs(stat.profitLoss) < 0.01) continue;
			const accounts = unitGroups[stat.unit] || [];
			if (accounts.length === 0) continue;

			const firstAccount = accounts[0].account_number;
			const pl = Math.round(stat.profitLoss * 100) / 100;
			if (pl > 0) {
				dpUpdates[firstAccount] = Math.round(((accountDeposits[firstAccount] ?? 0) + pl) * 100) / 100;
			} else if (pl < 0) {
				wdUpdates[firstAccount] = Math.round(((accountWithdrawals[firstAccount] ?? 0) + Math.abs(pl)) * 100) / 100;
			}
		}

		if (Object.keys(dpUpdates).length > 0) {
			accountDeposits = { ...accountDeposits, ...dpUpdates };
		}
		if (Object.keys(wdUpdates).length > 0) {
			accountWithdrawals = { ...accountWithdrawals, ...wdUpdates };
		}
		if (Object.keys(dpUpdates).length > 0 || Object.keys(wdUpdates).length > 0) {
			await updateAccountWithdrawalsAndDeposits();
		}

		adjustingAllPL = false;
	}

	let consolidatingUnits: Set<number> = new Set();
	let consolidatingAll = false;

	function getGroupWDDPSummary(unit: number) {
		const accounts = unitGroups[unit] || [];
		let totalWD = 0;
		let totalDP = 0;
		let maxWDAccount = '';
		let maxWDValue = 0;

		for (const a of accounts) {
			const wd = accountWithdrawals[a.account_number] ?? 0;
			const dp = accountDeposits[a.account_number] ?? 0;
			totalWD += wd;
			totalDP += dp;
			if (wd > maxWDValue) {
				maxWDValue = wd;
				maxWDAccount = a.account_number;
			}
		}

		if (!maxWDAccount && accounts.length > 0) maxWDAccount = accounts[0].account_number;

		const net = Math.round((totalWD - totalDP) * 100) / 100;
		return { accounts, totalWD, totalDP, net, maxWDAccount };
	}

	function isGroupNotNetted(unitAccounts: AccountSummary[]): boolean {
		const nonZeroCount = unitAccounts.filter((a) => (accountWithdrawals[a.account_number] ?? 0) > 0 || (accountDeposits[a.account_number] ?? 0) > 0).length;
		if (nonZeroCount > 1) return true;
		return unitAccounts.some((a) => (accountWithdrawals[a.account_number] ?? 0) > 0 && (accountDeposits[a.account_number] ?? 0) > 0);
	}

	async function consolidateGroupWDDP(unit: number) {
		const { accounts, totalWD, totalDP, net, maxWDAccount } = getGroupWDDPSummary(unit);
		if (accounts.length === 0 || !isGroupNotNetted(accounts)) return;

		const lines = accounts
			.filter((a) => (accountWithdrawals[a.account_number] ?? 0) > 0 || (accountDeposits[a.account_number] ?? 0) > 0)
			.map((a) => `  ${a.account_number}: WD ${formatNumber(accountWithdrawals[a.account_number] ?? 0)}, DP ${formatNumber(accountDeposits[a.account_number] ?? 0)}`)
			.join('\n');
		const resultLine = net > 0
			? `Net WD: ${formatNumber(net)} -> ${maxWDAccount}`
			: net < 0
				? `Net DP: ${formatNumber(Math.abs(net))} -> ${accounts[0].account_number}`
				: 'Net: 0 (all cleared)';

		if (!confirm(`Consolidate WD/DP for Unit ${unit}?\n\nCurrent:\n${lines}\n\nResult:\n  ${resultLine}\n  All other WD/DP cleared to 0`)) return;

		consolidatingUnits = new Set([...consolidatingUnits, unit]);
		await applyConsolidation(accounts, net, maxWDAccount);
		consolidatingUnits = new Set([...consolidatingUnits].filter((u) => u !== unit));
	}

	async function consolidateAllGroupsWDDP() {
		const groups: Array<{ unit: number; totalWD: number; totalDP: number; net: number; maxWDAccount: string; accounts: typeof summaries }> = [];

		for (const [unitStr] of Object.entries(unitGroups)) {
			const unit = parseInt(unitStr);
			const summary = getGroupWDDPSummary(unit);
			if (isGroupNotNetted(summary.accounts)) groups.push({ unit, ...summary });
		}

		if (groups.length === 0) return;

		const lines = groups.map((g) => `  Unit ${g.unit}: WD ${formatNumber(g.totalWD)}, DP ${formatNumber(g.totalDP)} -> Net ${g.net >= 0 ? 'WD' : 'DP'} ${formatNumber(Math.abs(g.net))}`).join('\n');
		if (!confirm(`Consolidate WD/DP for all groups?\n\n${lines}\n\nThis will net WD/DP for ${groups.length} group(s).`)) return;

		consolidatingAll = true;

		const newWD = { ...accountWithdrawals };
		const newDP = { ...accountDeposits };

		for (const g of groups) {
			for (const a of g.accounts) {
				newWD[a.account_number] = 0;
				newDP[a.account_number] = 0;
			}
			if (g.net > 0) {
				newWD[g.maxWDAccount] = g.net;
			} else if (g.net < 0) {
				newDP[g.accounts[0].account_number] = Math.abs(g.net);
			}
		}

		accountWithdrawals = newWD;
		accountDeposits = newDP;
		await updateAccountWithdrawalsAndDeposits();

		consolidatingAll = false;
	}

	async function applyConsolidation(accounts: typeof summaries, net: number, maxWDAccount: string) {
		const newWD = { ...accountWithdrawals };
		const newDP = { ...accountDeposits };

		for (const a of accounts) {
			newWD[a.account_number] = 0;
			newDP[a.account_number] = 0;
		}

		if (net > 0) {
			newWD[maxWDAccount] = net;
		} else if (net < 0) {
			newDP[accounts[0].account_number] = Math.abs(net);
		}

		accountWithdrawals = newWD;
		accountDeposits = newDP;
		await updateAccountWithdrawalsAndDeposits();
	}

	async function updateAccountWithdrawalsAndDeposits() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					account_withdrawals: accountWithdrawals,
					account_deposits: accountDeposits
				})
			});

			if (response.ok) {
				const data = await response.json();
				accountWithdrawals = data.account_withdrawals || accountWithdrawals;
				accountDeposits = data.account_deposits || accountDeposits;
				await fetchData();
			}
		} catch (error) {
			console.error('Error updating account withdrawals and deposits:', error);
		}
	}

	$: accountByNumber = (summaries || []).reduce(
		(map, a) => {
			(map as any)[a.account_number] = a;
			return map;
		},
		{} as Record<string, AccountSummary>
	);

	$: nonZeroAccountWDs = Object.entries(accountWithdrawals || {}).filter(
		([_, v]) => typeof v === 'number' && (v as number) > 0
	);

	$: nonZeroAccountDPs = Object.entries(accountDeposits || {}).filter(
		([_, v]) => typeof v === 'number' && (v as number) > 0
	);

	function groupNotesByUnit(notes: Record<string, number>) {
		const grouped: Record<number, Array<{ account_number: string; amount: number }>> = {};
		for (const [acc, amt] of Object.entries(notes || {})) {
			if (typeof amt !== 'number' || amt <= 0) continue;
			const u = accountByNumber[acc]?.unit ?? 0;
			if (!grouped[u]) grouped[u] = [];
			grouped[u].push({ account_number: acc, amount: amt });
		}
		return grouped;
	}

	$: wdByUnit = groupNotesByUnit(accountWithdrawals);
	$: dpByUnit = groupNotesByUnit(accountDeposits);
	$: draftWdByUnit = groupNotesByUnit(draftWithdrawals);
	$: draftDpByUnit = groupNotesByUnit(draftDeposits);

	function addUnitBrokerMinMargin() {
		const unit = parseInt(newUnitBrokerUnit);
		const name = newUnitBrokerName.trim();
		const margin = parseFloat(newUnitBrokerMargin);
		
		if (!isNaN(unit) && name && !isNaN(margin) && margin >= 0) {
			const next = cloneJson(draftBrokerMargins);
			if (!next[unit]) next[unit] = {};
			next[unit][name] = margin;
			draftBrokerMargins = next;
			newUnitBrokerUnit = '';
			newUnitBrokerName = '';
			newUnitBrokerMargin = '';
		}
	}

	function removeUnitBrokerMinMargin(unit: number, brokerName: string) {
		const next = cloneJson(draftBrokerMargins);
		if (next[unit]) {
			delete next[unit][brokerName];
			if (Object.keys(next[unit]).length === 0) delete next[unit];
			draftBrokerMargins = next;
		}
	}

	function updateUnitBrokerMargin(unit: number, oldBrokerName: string, newBrokerName: string, margin: number) {
		const next = cloneJson(draftBrokerMargins);
		if (!next[unit]) next[unit] = {};
		if (oldBrokerName !== newBrokerName && next[unit][oldBrokerName] !== undefined) {
			delete next[unit][oldBrokerName];
		}
		next[unit][newBrokerName] = margin;
		draftBrokerMargins = next;
	}

	function getUnitDisplayName(unit: number): string {
		return unitMappings[unit] || `Unit ${unit}`;
	}

	function getDraftUnitDisplayName(unit: number): string {
		return draftMappings[unit] || unitMappings[unit] || `Unit ${unit}`;
	}

	function getBrokerMinFor(name: string, unit?: number): number | undefined {
		if (!name || unit === undefined) return undefined;
		const lower = name.toLowerCase();
		
		// Check unit-specific margins only
		if (unitBrokerMinMargins[unit]) {
			for (const [k, v] of Object.entries(unitBrokerMinMargins[unit])) {
				if (k.toLowerCase() === lower) return v;
			}
		}
		
		return undefined;
	}

    function getUnitTargetEquity(unit: number): number {
        const cap = unitInitialCapitals[unit] ?? 0;
        return cap / 2;
    }

    function getUnitWarningPct(unit: number): number {
        return unitWarningEquityPercentages[unit] ?? 30;
    }

    function isLowEquityWarning(account: AccountSummary): boolean {
        const targetEquity = getUnitTargetEquity(account.unit);
        const warningThreshold = targetEquity * (getUnitWarningPct(account.unit) / 100);
        return account.latest_equity < warningThreshold;
    }

	function computeUnitDelta(accounts: AccountSummary[]): number | null {
		const buy = accounts.find(
			(a) => a.lastPositionSide === 'BUY' && (a.lastPositionEntryPrice ?? 0) > 0
		);
		const sell = accounts.find(
			(a) => a.lastPositionSide === 'SELL' && (a.lastPositionEntryPrice ?? 0) > 0
		);
		if (!buy || !sell) return null;
		const buyPrice = buy.lastPositionEntryPrice as number;
		const sellPrice = sell.lastPositionEntryPrice as number;
		return spreadDiffWholeTicks(buyPrice, sellPrice);
	}

	/** Top-summary legacy pair when unit has no order-json pairing (EA last-position only). */
	function computeLegacyUnitPair(unit: number, accounts: AccountSummary[]): UnitPair | null {
		const buy = accounts.find(
			(a) => a.lastPositionSide === 'BUY' && (a.lastPositionEntryPrice ?? 0) > 0
		);
		const sell = accounts.find(
			(a) => a.lastPositionSide === 'SELL' && (a.lastPositionEntryPrice ?? 0) > 0
		);
		if (!buy || !sell) return null;
		const buyPrice = buy.lastPositionEntryPrice as number;
		const sellPrice = sell.lastPositionEntryPrice as number;
		const diff = sellPrice - buyPrice;
		const buyLots = buy.lastSize ?? 0;
		const sellLots = sell.lastSize ?? 0;
		return {
			unit,
			symbol: '',
			buyAccount: buy.account_number,
			sellAccount: sell.account_number,
			buyBroker: buy.broker_name,
			sellBroker: sell.broker_name,
			buyPrice,
			sellPrice,
			diff,
			diffPoints: spreadDiffWholeTicks(buyPrice, sellPrice),
			lots: (buyLots + sellLots) / 2,
			buyLots,
			sellLots,
			openTime: buy.last_update || sell.last_update,
			buyOpenTime: buy.last_update || undefined,
			sellOpenTime: sell.last_update || undefined
		};
	}

	function applyCurrencyPayload(data: { currency?: unknown; fx?: FxQuote | null }) {
		if (data.currency) {
			currencySettings = normalizeCurrencySettings(data.currency);
		}
		if (data.fx && typeof data.fx.rate === 'number' && data.fx.rate > 0) {
			fxQuote = {
				...identityFxQuote(currencySettings),
				...data.fx,
				displayMode: data.fx.displayMode || identityFxQuote(currencySettings).displayMode,
				rawRate: typeof data.fx.rawRate === 'number' ? data.fx.rawRate : data.fx.rate,
				buffer: typeof data.fx.buffer === 'number' ? data.fx.buffer : currencySettings.liveBuffer
			};
		} else {
			fxQuote = identityFxQuote(currencySettings);
		}
	}

	function formatNumber(num: number, convert = true): string {
		const value = convert ? convertUsd(num, displayRate) : num;
		const result = new Intl.NumberFormat('th-TH', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		}).format(value);
		return result === '-0.00' ? '0.00' : result;
	}

	function formatPercent(num: number): string {
		const result = new Intl.NumberFormat('th-TH', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		}).format(num);
		return (result === '-0.00' ? '0.00' : result) + '%';
	}

	function formatDateTime(dateStr: string): string {
		// Show raw timestamp (no timezone conversion), format from UTC parts as DD/MM/YYYY HH:mm:ss
		const d = new Date(dateStr);
		const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);
		const dd = pad(d.getUTCDate());
		const mm = pad(d.getUTCMonth() + 1);
		const yyyy = d.getUTCFullYear();
		const HH = pad(d.getUTCHours());
		const min = pad(d.getUTCMinutes());
		const ss = pad(d.getUTCSeconds());
		return `${dd}/${mm}/${yyyy} ${HH}:${min}:${ss}`;
	}

	function shortName(name: string): string {
		if (!name) return '';
		return name.length > 8 ? name.slice(0, 8) + '~' : name;
	}

function truncateWithEllipsis(name: string, max: number = 6): string {
    if (!name) return '';
    return name.length > max ? name.slice(0, max) + '...' : name;
}

	const MASK = '#####';
	const brokerAliasPool = [
		'NORTH', 'RIDGE', 'QUILL', 'EMBER', 'HAVEN', 'PRISM', 'LEDGER', 'ORBIT',
		'FABLE', 'CIPHER', 'NOVA', 'WILLOW', 'HARBOR', 'QUARTZ', 'MAPLE', 'VISTA'
	].sort(() => Math.random() - 0.5);
	const brokerAliasByName: Record<string, string> = {};

	function bookValue(shown: string, reveal: boolean): string {
		return reveal ? shown : MASK;
	}

	function aliasBrokerName(name: string): string {
		const key = name || 'unknown';
		if (brokerAliasByName[key]) return brokerAliasByName[key];
		const used = Object.keys(brokerAliasByName).length;
		const base = brokerAliasPool[used % brokerAliasPool.length];
		const cycle = Math.floor(used / brokerAliasPool.length);
		const alias = cycle === 0 ? base : `${base}${cycle + 1}`;
		brokerAliasByName[key] = alias;
		return alias;
	}

	function bookBroker(name: string, reveal: boolean): string {
		return reveal ? truncateWithEllipsis(name, 6) : aliasBrokerName(name);
	}

	onMount(() => {
		revealBookValues = readStoredRevealBook();
		(async () => {
			await loadInitialCapital();
			await fetchData();
			startPolling();
		})();

		updateCountdown();
		countdownInterval = setInterval(updateCountdown, 1000);
		document.addEventListener('visibilitychange', handleVisibilityChange);
		window.addEventListener('pageshow', handlePageShow);

		return () => {
			document.removeEventListener('visibilitychange', handleVisibilityChange);
			window.removeEventListener('pageshow', handlePageShow);
			if (countdownInterval) {
				clearInterval(countdownInterval);
				countdownInterval = null;
			}
		};
	});

	onDestroy(() => {
		stopPolling();
	});

	async function saveSettings() {
		if (savingSettings) return;
		savingSettings = true;
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
                    unit_initial_capitals: draftCapitals,
                    unit_warning_equity_percentages: draftWarns,
					unit_mappings: draftMappings,
					unit_broker_min_margins: draftBrokerMargins,
					account_withdrawals: draftWithdrawals,
					account_deposits: draftDeposits,
					pl_alert: draftPlAlert,
					currency: draftCurrency
				})
			});
			if (response.ok) {
				const data = await response.json();
                initialCapital = data.initial_capital;
                unitInitialCapitals = data.unit_initial_capitals || draftCapitals;
                unitWarningEquityPercentages = data.unit_warning_equity_percentages || draftWarns;
				unitMappings = data.unit_mappings || draftMappings;
				unitBrokerMinMargins = data.unit_broker_min_margins || draftBrokerMargins;
				accountWithdrawals = data.account_withdrawals || draftWithdrawals;
				accountDeposits = data.account_deposits || draftDeposits;
				plAlertSettings = data.pl_alert || draftPlAlert;
				plAlertState = data.pl_alert_state || plAlertState;
				applyCurrencyPayload({ currency: data.currency || draftCurrency, fx: data.fx });
				showSettingsModal = false;
				location.reload();
			}
		} catch (e) {
			console.error('Error saving settings:', e);
		} finally {
			savingSettings = false;
		}
	}

	async function resetPlAlert(kind: 'profit' | 'loss') {
		if (resettingAlert) return;
		resettingAlert = kind;
		try {
			const response = await fetch('/api/alerts/reset', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ kind })
			});
			if (response.ok) {
				const data = await response.json();
				if (data.state) plAlertState = data.state;
			}
		} catch (error) {
			console.error('Error resetting PL alert:', error);
		} finally {
			resettingAlert = null;
		}
	}

	async function clearAllAccountData() {
		if (deletingData) return;
		deletingData = true;
		try {
			console.log('Sending DELETE request to /api/data/clear');
			const response = await fetch('/api/data/clear', {
				method: 'DELETE'
			});
			
			const result = await response.json();
			console.log('Delete response:', result);
			
			if (response.ok) {
				console.log('Delete successful, refreshing data...');
				// Refresh data after clearing
				await fetchData();
				showDeleteConfirmModal = false;
				showSettingsModal = false;
				console.log('Data refreshed successfully');
			} else {
				console.error('Failed to clear account data:', result);
				alert(`เกิดข้อผิดพลาด: ${result.error || 'ไม่สามารถลบข้อมูลได้'}`);
			}
		} catch (e) {
			console.error('Error clearing account data:', e);
			const msg = e instanceof Error ? e.message : 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้';
			alert(`เกิดข้อผิดพลาด: ${msg}`);
		} finally {
			deletingData = false;
		}
	}
</script>

<svelte:head>
	<title>Profit Monitor Dashboard</title>
	<meta
		name="viewport"
		content="width=device-width, initial-scale=1, viewport-fit=cover"
	/>
	<style>
		:root { background-color: #0a0a0a; }
	</style>
</svelte:head>

<div class="min-h-screen bg-[#0a0a0a] text-[#f5f5f5] pb-[max(1rem,env(safe-area-inset-bottom))]" class:hidden={!appReady}>
	<div class="sticky top-0 z-30 bg-[#0a0a0a] pt-[env(safe-area-inset-top)]">
		<div class="max-w-7xl mx-auto px-3 sm:px-4 py-3 flex items-start justify-between gap-3">
			<div class="min-w-0 flex-1">
				<div class="flex items-center gap-2">
					<CurrencyFlag currency={displayCurrency} />
					<div class="text-xs sm:text-sm tracking-wide">PROFIT MONITOR</div>
				</div>
				<div class="flex items-center gap-2 text-xs mt-1 min-w-0">
					{#if resumeLoading}
						<span title="Returned to app — fetching latest data">RESUMED · LOADING LATEST</span>
					{:else}
						{#if latestUpdate}
							<span class="tabular-nums">{formatDateTime(new Date(latestUpdate).toISOString())}</span>
						{/if}
						<span class="tabular-nums shrink-0" title="Next refresh">{String(countdownSeconds).padStart(2, '0')}s</span>
						<span
							class="shrink-0"
							title={fxQuote.displayMode === 'live+buffer'
								? `USD → ${displayCurrency} @ ${fxQuote.rawRate} − ${fxQuote.buffer} = ${fxQuote.rate} (${fxQuote.source})`
								: fxQuote.source === 'identity'
									? `${displayCurrency} · ${fxQuote.displayMode}`
									: `USD → ${displayCurrency} @ ${fxQuote.rate} (${fxQuote.source})`}
						>
							{displayCurrency}{#if displayCurrency !== 'USD'}
								· {formatNumber(fxQuote.rate, false)}
							{/if}
							· {fxQuote.displayMode}
						</span>
					{/if}
				</div>
			</div>
			<div class="flex items-center gap-1.5 shrink-0">
				<button
					on:click={() => setRevealBookValues(!revealBookValues)}
					class="fac-ghost fac-icon"
					class:fac-on={!revealBookValues}
					title={revealBookValues ? 'Hide values for capture' : 'Show values'}
					aria-label={revealBookValues ? 'Hide values for capture' : 'Show values'}
					aria-pressed={!revealBookValues}
				>
					{#if revealBookValues}
						<svg viewBox="0 0 24 24" aria-hidden="true">
							<path d="M2.5 12s3.5-7 9.5-7 9.5 7 9.5 7-3.5 7-9.5 7-9.5-7-9.5-7z" />
							<circle cx="12" cy="12" r="3" />
						</svg>
					{:else}
						<svg viewBox="0 0 24 24" aria-hidden="true">
							<path d="M2.5 12s3.5-7 9.5-7c2.2 0 4.1.9 5.7 2.1M21.5 12s-3.5 7-9.5 7c-2.2 0-4.1-.9-5.7-2.1" />
							<path d="M4 4l16 16" />
							<circle cx="12" cy="12" r="3" />
						</svg>
					{/if}
				</button>
				<button
					on:click={openSettings}
					class="fac-ghost fac-icon"
					title="Settings"
					aria-label="Open Settings"
				>
					<svg viewBox="0 0 24 24" aria-hidden="true">
						<circle cx="12" cy="12" r="2.5" />
						<path d="M10.2 3.6h3.6l.4 2.3 2.1-1 2.6 2.6-1 2.1 2.3.4v3.6l-2.3.4 1 2.1-2.6 2.6-2.1-1-.4 2.3h-3.6l-.4-2.3-2.1 1-2.6-2.6 1-2.1-2.3-.4V10l2.3-.4-1-2.1 2.6-2.6 2.1 1z" />
					</svg>
				</button>
				<button
					on:click={fetchData}
					class="fac-ghost fac-icon"
					title="Refresh"
					aria-label="Refresh"
					disabled={loading || isRefreshing || resumeLoading}
				>
					<svg viewBox="0 0 24 24" aria-hidden="true" class={isRefreshing || resumeLoading ? 'animate-spin' : ''}>
						<path d="M4.8 12a7.2 7.2 0 0112.4-5M19.2 12a7.2 7.2 0 01-12.4 5" />
						<path d="M17.2 3.8V7h-3.2M6.8 20.2V17H10" />
					</svg>
				</button>
			</div>
		</div>
	</div>

	<div class="max-w-7xl mx-auto px-3 sm:px-4 py-4 space-y-4">
		{#if loading}
			<div class="flex justify-center items-center h-64">
				<div class="animate-spin h-10 w-10 border-2 border-[#f5f5f5] border-t-transparent"></div>
			</div>
		{:else}

		<div class="pt-6 pb-4" data-fx-rate={displayRate}>
			{#if !isDataComplete}
				<span class="inline-block text-xs font-semibold fac-minus mb-2">Partial Data</span>
			{/if}
			<div class="flex items-center gap-3 sm:gap-4">
				<CurrencyFlag currency={displayCurrency} size={28} />
				<p
					class="fac-display text-5xl sm:text-6xl lg:text-8xl font-extrabold tracking-tight leading-none tabular-nums flex items-baseline gap-[0.18em] flex-wrap {!isDataComplete ? 'opacity-60' : ''} {Math.abs(adjustedProfitLoss) < 0.005 ? 'text-[#ececec]' : adjustedProfitLoss >= 0 ? 'fac-plus' : 'fac-minus'}"
				>
					<span>{adjustedProfitLoss >= 0.005 ? '+' : ''}{formatNumber(adjustedProfitLoss)}</span>
					{#if displayCurrency !== 'USD'}
						<span class="text-[0.28em] sm:text-[0.24em] lg:text-[0.22em] font-semibold tracking-normal text-[#ececec]">
							({adjustedProfitLoss >= 0.005 ? '+' : ''}{formatNumber(adjustedProfitLoss, false)} USD)
						</span>
					{/if}
				</p>
			</div>
			<p
				class="text-sm mt-3 tracking-tight {revealBookValues && Math.abs(adjustedProfitLossPercent) >= 0.005 ? (adjustedProfitLossPercent >= 0 ? 'fac-plus' : 'fac-minus') : 'text-[#ececec]'}"
			>
				{bookValue((adjustedProfitLossPercent >= 0.005 ? '+' : '') + formatNumber(adjustedProfitLossPercent, false), revealBookValues)}%
				{#if totalWaitingWD !== 0 || totalDeposits !== 0}
					<span class="text-[#ececec]">
						&nbsp; Total P/L
						<span class={revealBookValues ? (stats.profit_loss >= 0 ? 'fac-plus' : 'fac-minus') : ''}>{bookValue((stats.profit_loss >= 0 ? '+' : '') + formatNumber(stats.profit_loss), revealBookValues)}</span>
						{#if totalWaitingWD !== 0}
							&nbsp; WD <span class={revealBookValues ? (totalWaitingWD >= 0 ? 'fac-plus' : 'fac-minus') : ''}>{bookValue((totalWaitingWD >= 0 ? '+' : '') + formatNumber(totalWaitingWD), revealBookValues)}</span>
						{/if}
						{#if totalDeposits !== 0}
							&nbsp; DP <span class={revealBookValues ? 'fac-minus' : ''}>{bookValue('−' + formatNumber(totalDeposits), revealBookValues)}</span>
						{/if}
					</span>
				{/if}
			</p>

			<div class="fac-bars" aria-hidden="true">
				<i style="height:12px"></i><i style="height:22px"></i><i style="height:8px"></i><i style="height:26px"></i>
				<i style="height:14px"></i><i style="height:24px"></i><i style="height:10px"></i><i style="height:20px"></i>
			</div>
			<div class="flex items-center gap-3 flex-wrap text-xs">
				{#if snapshot}
					<span class={(snapshotDelta ?? 0) >= 0 ? 'fac-plus' : 'fac-minus'}>
						SNAPSHOT Δ {(snapshotDelta ?? 0) >= 0 ? '+' : ''}{formatNumber(snapshotDelta ?? 0)}
					</span>
				{/if}
				<button on:click={() => takeSnapshot('adjusted')} class="fac-ghost text-xs" disabled={snapshotLoading}>
					SNAPSHOT
				</button>
				{#if snapshot}
					<button on:click={clearSnapshot} class="fac-ghost text-xs" disabled={snapshotLoading}>
						CLEAR
					</button>
				{/if}
				{#if plAlertSettings.profitEnabled && plAlertState.profitPaused}
					<button
						on:click={() => resetPlAlert('profit')}
						class="fac-ghost text-xs"
						disabled={resettingAlert !== null}
					>
						{resettingAlert === 'profit' ? 'RESETTING...' : 'RESET PROFIT ALERT'}
					</button>
				{/if}
				{#if plAlertSettings.lossEnabled && plAlertState.lossPaused}
					<button
						on:click={() => resetPlAlert('loss')}
						class="fac-ghost text-xs"
						disabled={resettingAlert !== null}
					>
						{resettingAlert === 'loss' ? 'RESETTING...' : 'RESET LOSS ALERT'}
					</button>
				{/if}
			</div>
		</div>

		<div class="flex flex-wrap gap-x-6 gap-y-1 py-2 text-xs text-[#ececec]">
			<span>ACTIVE {stats.account_count}</span>
			<span>
				OPEN PAIRS {tradingPairs}
				{#if positivePairsCount > 0 || negativePairsCount > 0}
					<span class="fac-plus">+{positivePairsCount}</span>
					/
					<span class="fac-minus">−{negativePairsCount}</span>
				{/if}
			</span>
			<span class={lowEquityUnits.length > 0 ? 'fac-minus' : ''}>
				LOW EQUITY
				{#if lowEquityUnits.length > 0}
					{#each lowEquityUnits as u}
						#{u} {getUnitDisplayName(u)}
					{/each}
				{:else}
					--
				{/if}
			</span>
		</div>

		{#if positivePairs.length > 0 || negativePairs.length > 0}
		<div class="flex flex-wrap gap-x-4 gap-y-2 items-center py-2">
			<span>POSITIVE</span>
			{#each positivePairs as p}
				<span
					class="fac-plus tabular-nums"
					title={`Unit ${p.unit}${p.pairMagic !== undefined ? ` · magic ${p.pairMagic}` : ''}${p.symbol ? ' · ' + p.symbol : ''} · ${((p.buyLots + p.sellLots) / 2).toFixed(2)}L`}
				>
					+{Math.round(p.diffPoints)}
				</span>
			{/each}
			{#if positivePairs.length === 0}
				<span class="text-xs text-[#ececec]">--</span>
			{/if}
			<span>NEGATIVE</span>
			{#each negativePairs as p}
				<span
					class="fac-minus tabular-nums"
					title={`Unit ${p.unit}${p.pairMagic !== undefined ? ` · magic ${p.pairMagic}` : ''}${p.symbol ? ' · ' + p.symbol : ''} · ${((p.buyLots + p.sellLots) / 2).toFixed(2)}L`}
				>
					{Math.round(p.diffPoints)}
				</span>
			{/each}
			{#if negativePairs.length === 0}
				<span class="text-xs text-[#ececec]">--</span>
			{/if}
		</div>
		{/if}

		<div class="flex items-center justify-between gap-2 flex-wrap py-3">
			<div class="flex items-center gap-2">
				<button
					on:click={collapseAllUnits}
					class="fac-ghost fac-icon"
					title="Collapse all unit groups"
					aria-label="Collapse all unit groups"
				>
					<svg viewBox="0 0 24 24" aria-hidden="true">
						<path d="M6 15l6-6 6 6" />
					</svg>
				</button>
				<button
					on:click={expandAllUnits}
					class="fac-ghost fac-icon"
					title="Expand all unit groups"
					aria-label="Expand all unit groups"
				>
					<svg viewBox="0 0 24 24" aria-hidden="true">
						<path d="M6 9l6 6 6-6" />
					</svg>
				</button>
			</div>
			<button
				on:click={() => (showFilters = !showFilters)}
				class="fac-ghost fac-icon"
				class:fac-on={showFilters}
				title={showFilters ? 'Hide filters' : 'Filters'}
				aria-label={showFilters ? 'Hide filters' : 'Filters'}
				aria-pressed={showFilters}
			>
				<svg viewBox="0 0 24 24" aria-hidden="true">
					<path d="M4 6h16M7 12h10M10 18h4" />
				</svg>
			</button>
		</div>

		{#if showFilters}
		<div class="space-y-2 py-2">
			<div class="flex items-center gap-1.5 flex-wrap">
				<span class="text-xs text-[#ececec] font-medium">Broker:</span>
				{#each uniqueBrokersList as b}
					<button
						on:click={() => toggleBroker(b.name)}
						class="fac-ghost text-xs"
						class:fac-on={activeBrokers.has(b.name)}
						aria-pressed={activeBrokers.has(b.name)}
						title={`Toggle broker ${b.name}`}
					>
						{b.name} <span class="opacity-60">({b.count})</span>
					</button>
				{/each}
				<div class="ml-auto flex items-center gap-1">
					<button on:click={selectAllBrokers} class="text-xs px-1.5 py-0.5 rounded-md text-[#ececec] hover:text-[#f5f5f5] hover:bg-stone-700">All</button>
					<button on:click={clearAllBrokers} class="text-xs px-1.5 py-0.5 rounded-md text-[#ececec] hover:text-[#f5f5f5] hover:bg-stone-700">Clear</button>
				</div>
			</div>
			<div class="flex items-center gap-1.5 flex-wrap">
				<span class="text-xs text-[#ececec] font-medium">Account:</span>
				{#each uniqueAccountNamesList as a}
					<button
						on:click={() => toggleAccountName(a.name)}
						class="fac-ghost text-xs"
						class:fac-on={activeAccountNames.has(a.name)}
						aria-pressed={activeAccountNames.has(a.name)}
						title={`Toggle account ${a.name}`}
					>
						{shortName(a.name)} <span class="opacity-60">({a.count})</span>
					</button>
				{/each}
				<div class="ml-auto flex items-center gap-1">
					<button on:click={selectAllAccountNames} class="text-xs px-1.5 py-0.5 rounded-md text-[#ececec] hover:text-[#f5f5f5] hover:bg-stone-700">All</button>
					<button on:click={clearAllAccountNames} class="text-xs px-1.5 py-0.5 rounded-md text-[#ececec] hover:text-[#f5f5f5] hover:bg-stone-700">Clear</button>
				</div>
			</div>
		</div>
		{/if}

		<!-- Unit Groups -->
		<div class="space-y-3">

					{#each Object.entries(unitGroups) as [unitStr, accounts]}
						{@const unit = parseInt(unitStr)}
						{@const unitStat = unitStats.find((s) => s.unit === unit)}
						{@const sortedAccounts = [...accounts].sort(
							(a, b) =>
								a.broker_name.localeCompare(b.broker_name) ||
								a.account_number.localeCompare(b.account_number)
						)}
						{@const visibleAccounts = sortedAccounts.filter((a) => activeBrokers.has(a.broker_name) && activeAccountNames.has(a.account_name))}
						{@const unitHasStaleData = hasUnitStaleData(visibleAccounts)}
						{@const unitPairData = unitPairsMap[unit] || { pairs: [], unmatched: [] }}
						{@const unitPairs = unitPairData.pairs}
						{@const unitUnmatched = unitPairData.unmatched}
						{@const totalLots = unitPairs.reduce((s, p) => s + (p.buyLots + p.sellLots) / 2, 0)}
						
						{#if visibleAccounts.length > 0}
						<div class="py-3 {unitUnmatched.length > 0 ? 'fac-unit-solo' : unitHasOpenTrades(unitPairs, unitUnmatched) ? 'fac-unit-open' : ''}">
							<!-- Unit Header Row 1: Name + badges -->
							<div 
								class="px-4 py-2.5 cursor-pointer transition-colors {accounts.some(isLowEquityWarning) ? 'bg-red-900/20 hover:bg-red-900/30' : 'hover:bg-stone-700/50'}"
								on:click={() => {
									unitVisibility = { ...unitVisibility, [unit]: !(unitVisibility[unit] !== false) };
								}}
								on:keydown={(e) => {
									if (e.key === 'Enter' || e.key === ' ') {
										e.preventDefault();
										unitVisibility = { ...unitVisibility, [unit]: !(unitVisibility[unit] !== false) };
									}
								}}
								role="button"
								tabindex="0"
								title="Click to expand/collapse unit group"
							>
								<!-- Row 1: Unit name + status badges -->
								<div class="flex items-center justify-between">
									<div class="flex items-center gap-2">
										<svg 
											class="w-3.5 h-3.5 text-[#ececec] transition-transform duration-200 flex-shrink-0"
											class:rotate-90={unitVisibility[unit] !== false}
											fill="none" stroke="currentColor" viewBox="0 0 24 24"
										>
											<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
										</svg>
										<h3 class="fac-display text-xl font-bold">
											{unit === 0 ? 'Unknown Unit' : getUnitDisplayName(unit)}
										</h3>
										<span class="text-sm text-[#ececec]">#{unit}</span>
										{#if accounts.some(isLowEquityWarning)}
											<span class="w-1.5 h-1.5 rounded-full bg-red-400 flex-shrink-0" title="Low equity"></span>
										{/if}
										{#if unitHasStaleData}
											<span class="w-1.5 h-1.5 rounded-full bg-orange-400 flex-shrink-0" title="Stale data"></span>
										{/if}
										{#if unitStat}
											{#if isGroupNotNetted(unitGroups[unit] || [])}
												<button on:click|stopPropagation={() => consolidateGroupWDDP(unit)} disabled={consolidatingUnits.has(unit)} class="text-[10px] px-1.5 py-0.5 rounded font-medium bg-cyan-900/40 hover:bg-cyan-900/60 text-cyan-400 disabled:opacity-50 transition-colors">
													{consolidatingUnits.has(unit) ? '...' : 'Simplify WD/DP'}
												</button>
											{/if}
										{/if}
									</div>
									<div class="flex items-center gap-1.5 flex-shrink-0">
										{#if unitPairs.length > 0}
											<span class="text-xs font-semibold" title="Paired BUY/SELL legs with the same magic number across accounts">
												{bookValue(String(unitPairs.length), revealBookValues)} pair{unitPairs.length > 1 ? 's' : ''}
											</span>
											{#if totalLots > 0}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-violet-900/40 text-violet-400" title="Total lots across pairs">
													{bookValue(totalLots.toFixed(2), revealBookValues)}L
												</span>
											{/if}
											{#if unitUnmatched.length > 0}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-amber-900/40 text-amber-300" title="Legs without opposite side (verify magic matches across accounts)">
													{unitUnmatched.length} solo
												</span>
											{/if}
										{:else if unitUnmatched.length > 0}
											<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-amber-900/40 text-amber-300" title="No magic match or missing magic on one side — legs stay unpaired">
												{unitUnmatched.length} unpaired
											</span>
											{@const soloLots = unitUnmatched.reduce((s, o) => s + o.lots, 0)}
											{#if soloLots > 0}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-violet-900/40 text-violet-400">
													{bookValue(soloLots.toFixed(2), revealBookValues)}L
												</span>
											{/if}
										{:else}
											{@const legacyDelta = computeUnitDelta(accounts)}
											{#if legacyDelta !== null}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold {legacyDelta >= 0 ? 'bg-emerald-900/40 fac-plus' : 'bg-red-900/40 fac-minus'}">
													{legacyDelta > 0 ? '+' : ''}{legacyDelta.toFixed(0)} pts
												</span>
											{/if}
											{@const accountWithPosition = visibleAccounts.find((a) => (a.lastSize || 0) > 0)}
											{@const positionLots = accountWithPosition?.lastSize || 0}
											{@const positionSide = accountWithPosition?.lastPositionSide}
											{#if positionLots > 0}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-violet-900/40 text-violet-400">
													{bookValue(positionLots.toFixed(2), revealBookValues)}L
												</span>
												{#if positionSide === 'BUY' || positionSide === 'SELL'}
													<span class="text-xs px-1.5 py-0.5 rounded-md font-bold {positionSide === 'BUY' ? 'bg-sky-900/40 text-sky-400' : 'bg-orange-900/40 text-orange-400'}">
														{positionSide}
													</span>
												{/if}
											{/if}
										{/if}
									</div>
								</div>

								<!-- Pair chips: list each pair's diff and lots -->
								{#if unitPairs.length > 0}
									<div class="flex items-center gap-1.5 mt-1.5 flex-wrap">
										{#each unitPairs as p}
											<span
												class="inline-flex items-center gap-1 text-[10px] font-medium {p.diffPoints >= 0 ? 'fac-plus' : 'fac-minus'}"
												title={`${p.pairMagic !== undefined ? `Magic ${p.pairMagic}` : 'Pair'}${p.symbol ? ' · ' + p.symbol : ''} · BUY ${p.buyPrice} / SELL ${p.sellPrice} · ${formatDateTime(p.openTime)}`}
											>
												{#if p.pairMagic !== undefined}
													<span class="text-[9px] font-normal opacity-45 tabular-nums">#{p.pairMagic}</span>
												{:else}
													<span class="text-[9px] font-normal opacity-45">—</span>
												{/if}
												<span class="font-semibold">{p.diffPoints >= 0 ? '+' : ''}{p.diffPoints.toFixed(0)}</span>
												<span class="opacity-70">·</span>
												<span>{bookValue(((p.buyLots + p.sellLots) / 2).toFixed(2), revealBookValues)}L</span>
											</span>
										{/each}
									</div>
								{/if}

								<!-- Row 2: Stats line + P/L -->
								{#if unitStat}
									{@const unitWD = (unitGroups[unit] || []).reduce((s, a) => s + (accountWithdrawals[a.account_number] ?? 0), 0)}
									{@const unitDP = (unitGroups[unit] || []).reduce((s, a) => s + (accountDeposits[a.account_number] ?? 0), 0)}
									<div class="flex items-center justify-between mt-1.5">
										<div class="flex items-center gap-x-3 gap-y-0.5 flex-wrap text-xs text-[#ececec]">
											<span>C: {bookValue(formatNumber(unitInitialCapitals[unit] ?? 0), revealBookValues)}</span>
											<span>T: {bookValue(formatNumber(unitStat.totalBalance), revealBookValues)}</span>
											{#if unitWD > 0}
												<span>WD: {bookValue('+' + formatNumber(unitWD), revealBookValues)}</span>
											{/if}
											{#if unitDP > 0}
												<span>DP: {bookValue('-' + formatNumber(unitDP), revealBookValues)}</span>
											{/if}
										</div>
										<div class="flex flex-col items-end flex-shrink-0 ml-3 leading-tight">
											<span class="text-xs font-semibold {Math.abs(unitStat.profitLoss) < 0.005 ? 'text-[#ececec]' : unitStat.profitLoss >= 0 ? 'fac-plus' : 'fac-minus'}">
												{unitStat.profitLoss >= 0.005 ? '+' : ''}{formatNumber(unitStat.profitLoss)}
											</span>
											{#if unitInitialCapitals[unit] && unitInitialCapitals[unit] > 0}
												{@const pct = (unitStat.profitLoss / unitInitialCapitals[unit]) * 100}
												{@const pctStr = pct.toFixed(1) === '-0.0' ? '0.0' : pct.toFixed(1)}
												<span class="text-[10px] {revealBookValues && Math.abs(pct) >= 0.005 ? (pct >= 0 ? 'fac-plus' : 'fac-minus') : 'text-[#ececec]'}">
													{bookValue((pct >= 0.005 ? '+' : '') + pctStr, revealBookValues)}%
												</span>
											{/if}
										</div>
									</div>
								{/if}

								<!-- Row 3: Broker D/W breakdown (compact) -->
								{#if true}
									{@const targetEquity = getUnitTargetEquity(unit)}
									{@const sumsByBroker = (() => {
										const map: Record<string, { d: number; w: number }> = {};
										for (const a of visibleAccounts || []) {
											const broker = a.broker_name || '';
											if (!map[broker]) map[broker] = { d: 0, w: 0 };
											const diff = a.latest_equity - targetEquity;
											if (diff >= 0) map[broker].w += diff;
											else map[broker].d += -diff;
										}
										return map;
									})()}
									{@const nonZeroEntries = Object.entries(sumsByBroker).filter(([_, s]) => (s?.d || 0) > 0 || (s?.w || 0) > 0)}
									{#if nonZeroEntries.length > 0}
										<div class="flex items-center gap-1.5 mt-1 flex-wrap">
											{#each nonZeroEntries as [broker, s]}
												<div class="flex items-center gap-1 text-[10px]">
													<span class="text-[#ececec]">{bookBroker(broker, revealBookValues)}</span>
													{#if s.d > 0}<span class="fac-plus font-medium">D{bookValue(formatNumber(s.d), revealBookValues)}</span>{/if}
													{#if s.w > 0}<span class="fac-minus font-medium">W{bookValue(formatNumber(s.w), revealBookValues)}</span>{/if}
												</div>
											{/each}
										</div>
									{/if}
								{/if}
							</div>
							
							{#if unitVisibility[unit] !== false}
							{#if unitStat && Math.abs(unitStat.profitLoss) >= 0.01}
								<div class="px-4 py-1.5 border-t border-stone-700/50 flex items-center justify-end">
									<button on:click={() => adjustUnitPLToZero(unit)} disabled={adjustingPLUnits.has(unit)} class="text-[11px] min-h-9 px-2.5 rounded font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
										{adjustingPLUnits.has(unit) ? '...' : 'Set P/L Zero'}
									</button>
								</div>
							{/if}

							{#if unitPairs.length > 0 || unitUnmatched.length > 0}
								<div class="px-4 py-2 border-t border-stone-700/50 bg-stone-900/40">
									<div class="flex items-center justify-between mb-1.5">
										<span class="text-[10px] font-semibold text-[#ececec] uppercase tracking-wider">Open Pairs ({unitPairs.length})</span>
										{#if totalLots > 0}
											<span class="text-[10px] text-[#ececec]">Total {bookValue(totalLots.toFixed(2), revealBookValues)}L</span>
										{/if}
									</div>
									<div class="md:hidden space-y-2">
										{#each unitPairs as p}
											<div class="py-2.5">
												<div class="flex items-start justify-between gap-2">
													<div class="min-w-0">
														<div class="font-mono text-sm text-[#f5f5f5] truncate">{p.symbol || '-'}</div>
														<div class="text-[10px] text-[#ececec] tabular-nums">{p.pairMagic !== undefined ? `#${p.pairMagic}` : '—'}</div>
													</div>
													<div class="text-right shrink-0">
														<div class="text-sm font-semibold tabular-nums {p.diffPoints >= 0 ? 'fac-plus' : 'fac-minus'}">
															{p.diffPoints >= 0 ? '+' : ''}{p.diffPoints.toFixed(0)} pts
														</div>
														<div class="text-[11px] text-[#ececec] tabular-nums">
															{p.buyLots.toFixed(2)}L
															{#if Math.abs(p.buyLots - p.sellLots) > 0.001}
																<span class="text-[#ececec]"> / {p.sellLots.toFixed(2)}</span>
															{/if}
														</div>
													</div>
												</div>
												<div class="mt-2 grid grid-cols-2 gap-2 text-[11px]">
													<div>
														<div class="text-[#ececec]">BUY</div>
														<div class="text-sky-300 tabular-nums">{p.buyPrice}</div>
														<div class="text-[#ececec] tabular-nums">{p.buyOpenTime ? formatDateTime(p.buyOpenTime) : '—'}</div>
													</div>
													<div class="text-right">
														<div class="text-[#ececec]">SELL</div>
														<div class="text-orange-300 tabular-nums">{p.sellPrice}</div>
														<div class="text-[#ececec] tabular-nums">{p.sellOpenTime ? formatDateTime(p.sellOpenTime) : '—'}</div>
													</div>
												</div>
											</div>
										{/each}
										{#each unitUnmatched as o}
											<div class="rounded-lg border border-amber-800/40 bg-amber-900/10 px-3 py-2.5">
												<div class="flex items-start justify-between gap-2">
													<div class="min-w-0">
														<div class="font-mono text-sm text-[#f5f5f5] truncate">{o.symbol || '-'}</div>
														<div class="text-[10px] text-amber-400 tabular-nums">{typeof o.magic === 'number' ? `!#${o.magic}` : '!—'}</div>
													</div>
													<div class="text-right shrink-0">
														<div class="text-sm font-semibold text-amber-400 italic">solo</div>
														<div class="text-[11px] text-[#ececec] tabular-nums">{o.lots.toFixed(2)}L</div>
													</div>
												</div>
												<div class="mt-2 text-[11px]">
													<div class={o.side === 'BUY' ? 'text-sky-300' : 'text-orange-300'}>
														{o.side} {o.price}
													</div>
													<div class="text-[#ececec] tabular-nums">{o.openTime ? formatDateTime(o.openTime) : '—'}</div>
												</div>
											</div>
										{/each}
									</div>
									<div class="hidden md:block overflow-x-auto">
										<table class="w-full text-[11px]">
											<thead>
												<tr class="border-b border-stone-700/60 text-[#ececec]">
													<th class="text-left py-1 px-2 font-medium">#</th>
													<th class="text-left py-1 px-2 font-medium">Symbol</th>
													<th class="text-right py-1 px-2 font-medium">BUY Price</th>
													<th class="text-right py-1 px-2 font-medium">SELL Price</th>
													<th class="text-right py-1 px-2 font-medium">Diff (pts)</th>
													<th class="text-right py-1 px-2 font-medium">Lots</th>
													<th class="text-left py-1 px-2 font-medium">BUY Open Time</th>
													<th class="text-left py-1 px-2 font-medium">SELL Open Time</th>
												</tr>
											</thead>
											<tbody>
												{#each unitPairs as p}
													<tr class="border-b border-stone-700/30">
														<td class="py-1 px-2 text-[#ececec] font-mono tabular-nums text-[10px] opacity-80">{p.pairMagic !== undefined ? `#${p.pairMagic}` : '—'}</td>
														<td class="py-1 px-2 text-[#f5f5f5] font-mono">{p.symbol || '-'}</td>
														<td class="py-1 px-2 text-right text-sky-300 tabular-nums" title={`Account ${p.buyAccount} @ ${p.buyBroker}`}>{p.buyPrice}</td>
														<td class="py-1 px-2 text-right text-orange-300 tabular-nums" title={`Account ${p.sellAccount} @ ${p.sellBroker}`}>{p.sellPrice}</td>
														<td class="py-1 px-2 text-right font-semibold tabular-nums {p.diffPoints >= 0 ? 'fac-plus' : 'fac-minus'}">
															{p.diffPoints >= 0 ? '+' : ''}{p.diffPoints.toFixed(0)}
														</td>
														<td class="py-1 px-2 text-right text-[#f5f5f5] tabular-nums">
															{p.buyLots.toFixed(2)}
															{#if Math.abs(p.buyLots - p.sellLots) > 0.001}
																<span class="text-[#ececec]"> / {p.sellLots.toFixed(2)}</span>
															{/if}
														</td>
														<td class="py-1 px-2 text-left text-[#ececec] tabular-nums">{p.buyOpenTime ? formatDateTime(p.buyOpenTime) : '—'}</td>
														<td class="py-1 px-2 text-left text-[#ececec] tabular-nums">{p.sellOpenTime ? formatDateTime(p.sellOpenTime) : '—'}</td>
													</tr>
												{/each}
												{#each unitUnmatched as o}
													<tr class="border-b border-stone-700/30 bg-amber-900/10">
														<td class="py-1 px-2 text-amber-500 font-mono tabular-nums text-[10px]">{typeof o.magic === 'number' ? `!#${o.magic}` : '!—'}</td>
														<td class="py-1 px-2 text-[#f5f5f5] font-mono">{o.symbol || '-'}</td>
														<td class="py-1 px-2 text-right tabular-nums {o.side === 'BUY' ? 'text-sky-300' : 'text-stone-600'}" title={o.side === 'BUY' ? `Account ${o.account_number} @ ${o.broker_name}` : ''}>
															{o.side === 'BUY' ? o.price : '-'}
														</td>
														<td class="py-1 px-2 text-right tabular-nums {o.side === 'SELL' ? 'text-orange-300' : 'text-stone-600'}" title={o.side === 'SELL' ? `Account ${o.account_number} @ ${o.broker_name}` : ''}>
															{o.side === 'SELL' ? o.price : '-'}
														</td>
														<td class="py-1 px-2 text-right text-amber-400 italic">solo</td>
														<td class="py-1 px-2 text-right text-[#f5f5f5] tabular-nums">{o.lots.toFixed(2)}</td>
														<td class="py-1 px-2 text-left text-[#ececec] tabular-nums">{o.side === 'BUY' && o.openTime ? formatDateTime(o.openTime) : '—'}</td>
														<td class="py-1 px-2 text-left text-[#ececec] tabular-nums">{o.side === 'SELL' && o.openTime ? formatDateTime(o.openTime) : '—'}</td>
													</tr>
												{/each}
											</tbody>
										</table>
									</div>
								</div>
							{/if}
							<!-- Compact Table View -->
							<div class="md:hidden divide-y divide-[#3a3a3a] fac-sheet my-3">
								{#each visibleAccounts as account}
									{@const dataAge = getDataAge(account.last_update)}
									{@const adjust = getUnitTargetEquity(account.unit) - account.latest_equity}
									<div class="px-4 py-3 space-y-2 {dataAge.status === 'fresh' && isLowEquityWarning(account) ? 'bg-red-900/20' : ''}">
										<div class="flex items-start justify-between gap-2">
											<div class="min-w-0">
												<div class="font-mono font-semibold text-[#f5f5f5] text-sm">{account.account_number}</div>
												<div class="text-xs text-[#ececec] truncate">{account.account_name} · {account.broker_name}</div>
											</div>
											<div class="text-right shrink-0">
												{#if dataAge.status === 'stale'}
													<span class="text-xs font-semibold text-orange-400">Stale {dataAge.minutes}m</span>
												{:else}
													<span class="text-xs font-semibold fac-plus">Fresh</span>
												{/if}
												<div class="text-[10px] text-[#ececec] tabular-nums">{formatDateTime(account.last_update)}</div>
											</div>
										</div>
										<div class="grid grid-cols-2 gap-2 text-xs">
											<div>
												<div class="text-[#ececec]">Balance</div>
												<div class="font-medium text-[#f5f5f5] tabular-nums">{formatNumber(account.latest_balance)}</div>
											</div>
											<div>
												<div class="text-[#ececec]">Equity</div>
												<div class="font-medium text-[#f5f5f5] tabular-nums">{formatNumber(account.latest_equity)}</div>
											</div>
											<div>
												<div class="text-[#ececec]">Adjust</div>
												<div class="font-medium tabular-nums {adjust > 0 ? 'fac-plus' : adjust < 0 ? 'fac-minus' : 'text-[#ececec]'}">
													{#if adjust > 0}
														D {formatNumber(Math.abs(adjust))}
													{:else if adjust < 0}
														W {formatNumber(Math.abs(adjust))}
													{:else}
														{formatNumber(0)}
													{/if}
												</div>
											</div>
										</div>
										<div class="grid grid-cols-2 gap-2">
											<label class="block text-[11px] text-[#ececec]">
												WD Note (+)
												<input
													type="number"
													min="0"
													step="100"
													value={accountWithdrawals[account.account_number] ?? 0}
													on:change={(e) => handleAccountWithdrawalChange(account.account_number, e)}
													class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
												/>
											</label>
											<label class="block text-[11px] text-[#ececec]">
												DP Note (-)
												<input
													type="number"
													min="0"
													step="100"
													value={accountDeposits[account.account_number] ?? 0}
													on:change={(e) => handleAccountDepositChange(account.account_number, e)}
													class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
												/>
											</label>
										</div>
									</div>
								{/each}
							</div>
							<div class="hidden md:block overflow-x-auto fac-sheet mx-0 my-3">
								<table class="w-full text-xs">
									<thead>
										<tr class="border-b border-stone-700">
											<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">Adjust</th>
											<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Account / Name</th>
											<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Broker</th>
											<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">Balance</th>
											<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">Equity</th>
											<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">WD Note (+)</th>
											<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">DP Note (-)</th>
											<th class="text-center py-1.5 px-2 text-[#ececec] font-medium">Status</th>
											<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Updated</th>
										</tr>
									</thead>
									<tbody>
										{#each visibleAccounts as account}
											{@const dataAge = getDataAge(account.last_update)}
											<tr
												class="border-b border-stone-700/50 hover:bg-stone-700/30 transition-colors {dataAge.status === 'fresh' && isLowEquityWarning(account) ? 'bg-red-900/20' : ''}"
											>
                                            <td
													class="py-1.5 px-2 text-right font-medium text-xs"
                                                class:fac-minus={getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                class:fac-plus={getUnitTargetEquity(account.unit) - account.latest_equity > 0}
												>
                                                {#if getUnitTargetEquity(account.unit) - account.latest_equity > 0}
                                                    D {formatNumber(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity))}
                                                {:else if getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                    W {formatNumber(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity))}
													{:else}
														{formatNumber(0)}
													{/if}
												</td>
												<td class="py-1.5 px-2">
													<div class="flex flex-col leading-tight">
														<span class="font-mono font-semibold text-[#f5f5f5] text-xs">
															{account.account_number}
														</span>
														<span class="text-[#ececec] text-xs truncate" title={account.account_name}
															>{shortName(account.account_name)}</span
														>
													</div>
												</td>
												<td class="py-1.5 px-2 text-[#ececec] text-xs">{account.broker_name}</td>
												<td class="py-1.5 px-2 text-right font-medium text-[#f5f5f5] text-xs"
													>{formatNumber(account.latest_balance)}</td
												>
												<td class="py-1.5 px-2 text-right font-medium text-[#f5f5f5] text-xs"
													>{formatNumber(account.latest_equity)}</td
												>
												<td class="py-1.5 px-2 text-right">
													<input
														type="number"
														min="0"
														step="100"
														value={accountWithdrawals[account.account_number] ?? 0}
														on:change={(e) =>
															handleAccountWithdrawalChange(account.account_number, e)}
														class="w-20 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-1.5 py-0.5 text-right text-xs focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
													/>
												</td>
												<td class="py-1.5 px-2 text-right">
													<input
														type="number"
														min="0"
														step="100"
														value={accountDeposits[account.account_number] ?? 0}
														on:change={(e) =>
															handleAccountDepositChange(account.account_number, e)}
														class="w-20 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-1.5 py-0.5 text-right text-xs focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
													/>
												</td>
												<td class="py-1.5 px-2 text-center">
													{#if dataAge.status === 'stale'}
														<span class="text-orange-500 font-bold" title="ข้อมูลเก่ากว่า 5 นาที ({dataAge.minutes} นาที)">
															~
														</span>
													{:else}
														<span class="fac-plus" title="ข้อมูลใหม่">
															✓
														</span>
													{/if}
												</td>
												<td class="py-1.5 px-2 text-[#ececec] text-xs"
													>{formatDateTime(account.last_update)}</td
												>
											</tr>
										{/each}
									</tbody>
								</table>
							</div>
							{/if}
						</div>
						{/if}
					{/each}
		</div>

		<!-- Sum Total -->
		{#if unitStats.length > 0}
			{@const brokerTree = (() => {
				const map: Record<string, { equity: number; names: Record<string, { equity: number; accounts: { number: string; equity: number }[] }> }> = {};
				for (const a of summaries || []) {
					if (!activeBrokers.has(a.broker_name) || !activeAccountNames.has(a.account_name)) continue;
					const broker = a.broker_name || 'Unknown';
					const name = a.account_name || 'Unknown';
					if (!map[broker]) map[broker] = { equity: 0, names: {} };
					if (!map[broker].names[name]) map[broker].names[name] = { equity: 0, accounts: [] };
					map[broker].equity += a.latest_equity;
					map[broker].names[name].equity += a.latest_equity;
					map[broker].names[name].accounts.push({ number: a.account_number, equity: a.latest_equity });
				}
				return Object.entries(map).sort((a, b) => b[1].equity - a[1].equity);
			})()}
			<div class="py-4">
				<div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
					<div class="flex flex-col">
						<span class="text-xs font-medium tracking-wider">TOTAL</span>
						{#if initialCapital > 0}
							<span class="text-[10px] text-[#ececec] mt-0.5">Capital: {formatNumber(initialCapital)}</span>
						{/if}
					</div>
					<div class="flex items-center gap-2 flex-wrap">
						<span class="text-lg font-bold text-[#f5f5f5]">
							{formatNumber(unitStats.reduce((sum, s) => sum + s.totalBalance, 0))}
						</span>
						{#if unitStats.some((s) => Math.abs(s.profitLoss) >= 0.01)}
							<button on:click={adjustAllGroupsPL} disabled={adjustingAllPL} class="text-[11px] min-h-9 px-2.5 rounded-md font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
								{adjustingAllPL ? '...' : 'Set P/L Zero All'}
							</button>
						{/if}
						{#if Object.values(unitGroups).some((accs) => isGroupNotNetted(accs))}
							<button on:click={consolidateAllGroupsWDDP} disabled={consolidatingAll} class="text-[11px] min-h-9 px-2.5 rounded-md font-medium bg-cyan-900/40 hover:bg-cyan-900/60 text-cyan-400 disabled:opacity-50 transition-colors">
								{consolidatingAll ? '...' : 'Simplify WD/DP All'}
							</button>
						{/if}
					</div>
				</div>
				{#if brokerTree.length > 0}
					<div class="flex flex-col gap-1.5 mt-2.5">
						{#each brokerTree as [broker, brokerData]}
							<div>
								<!-- Level 1: Broker -->
								<button
									on:click={() => {
										if (expandedBrokers.has(broker)) {
											expandedBrokers.delete(broker);
										} else {
											expandedBrokers.add(broker);
										}
										expandedBrokers = expandedBrokers;
									}}
									class="w-full flex items-center justify-between text-xs text-[#ececec] bg-stone-800/60 hover:bg-stone-700/60 rounded-lg px-2.5 py-1.5 transition-colors"
								>
									<span class="flex items-center gap-1.5">
										<svg class="w-3 h-3 text-[#ececec] transition-transform {expandedBrokers.has(broker) ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" /></svg>
										{broker}
										<span class="text-[10px] text-[#ececec]">({Object.keys(brokerData.names).length})</span>
									</span>
									<span class="font-semibold text-[#f5f5f5]">{formatNumber(brokerData.equity)}</span>
								</button>
								{#if expandedBrokers.has(broker)}
									<div class="ml-5 mt-1 flex flex-col gap-1">
										{#each Object.entries(brokerData.names).sort((a, b) => b[1].equity - a[1].equity) as [name, nameData]}
											{@const nameKey = `${broker}::${name}`}
											<div>
												<!-- Level 2: Account Name -->
												{#if nameData.accounts.length > 1}
													<button
														on:click={() => {
															if (expandedBrokerNames.has(nameKey)) {
																expandedBrokerNames.delete(nameKey);
															} else {
																expandedBrokerNames.add(nameKey);
															}
															expandedBrokerNames = expandedBrokerNames;
														}}
														class="w-full flex items-center justify-between text-[11px] text-[#ececec] hover:bg-stone-700/40 rounded-md px-2.5 py-1 transition-colors"
													>
														<span class="flex items-center gap-1.5">
															<svg class="w-2.5 h-2.5 text-[#ececec] transition-transform {expandedBrokerNames.has(nameKey) ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" /></svg>
															<span class="truncate">{name}</span>
															<span class="text-[10px] text-[#ececec]">({nameData.accounts.length})</span>
														</span>
														<span class="font-medium text-[#f5f5f5] whitespace-nowrap">{formatNumber(nameData.equity)}</span>
													</button>
													{#if expandedBrokerNames.has(nameKey)}
														<div class="ml-5 mt-0.5 space-y-0.5">
															{#each nameData.accounts.sort((a, b) => b.equity - a.equity) as acct}
																<div class="flex items-center justify-between text-[10px] px-2.5 py-0.5 rounded bg-stone-800/40">
																	<span class="text-[#ececec] tabular-nums">{acct.number}</span>
																	<span class="font-medium text-[#ececec] whitespace-nowrap">{formatNumber(acct.equity)}</span>
																</div>
															{/each}
														</div>
													{/if}
												{:else}
													<!-- Single account under this name — show inline -->
													<div class="flex items-center justify-between text-[11px] text-[#ececec] px-2.5 py-1 rounded-md">
														<span class="flex items-center gap-1.5">
															<span class="w-2.5"></span>
															<span class="truncate">{name}</span>
															<span class="text-[10px] text-[#ececec]">{nameData.accounts[0].number}</span>
														</span>
														<span class="font-medium text-[#f5f5f5] whitespace-nowrap">{formatNumber(nameData.equity)}</span>
													</div>
												{/if}
											</div>
										{/each}
									</div>
								{/if}
							</div>
						{/each}
					</div>
				{/if}
			</div>
		{/if}

		{#if summaries.length === 0}
			<div class="py-12 text-center">
				<svg class="mx-auto h-10 w-10 text-stone-600 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
				</svg>
				<h3 class="text-base font-medium text-[#f5f5f5] mb-1">No Data Available</h3>
				<p class="text-sm text-[#ececec]">Waiting for EA to send account data...</p>
			</div>
		{/if}

		{/if}
	</div>
</div>

<!-- Settings Modal -->
{#if showSettingsModal}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 overflow-y-auto flex items-stretch md:items-center justify-center p-0 md:p-6"
		on:click={closeSettings}
		on:keydown={(e) => e.key === 'Escape' && closeSettings()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="settings-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] text-[#f5f5f5] w-full max-w-7xl md:mx-4 md:my-8 flex flex-col h-full md:h-auto max-h-none md:max-h-[85vh] border-0 md:border md:border-[#f5f5f5]"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="flex justify-between items-center px-4 pt-[max(1rem,env(safe-area-inset-top))] pb-3 sm:p-6 sm:pb-4">
				<h2 id="settings-title" class="text-xl font-semibold text-[#f5f5f5]">Settings</h2>
				<button
					on:click={closeSettings}
					class="text-[#ececec] hover:text-[#f5f5f5] min-h-11 min-w-11 inline-flex items-center justify-center rounded-lg hover:bg-stone-700 transition-colors"
					aria-label="Close Settings"
				>
					<svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M6 18L18 6M6 6l12 12"
						/>
					</svg>
				</button>
			</div>
            <div class="flex-1 overflow-y-auto px-4 sm:px-6 pb-4 space-y-6">
                <div>
                    <fieldset>
                        <legend class="block text-sm font-medium text-[#f5f5f5] mb-2">Display Currency</legend>
                        <div class="flex flex-wrap items-center gap-2 mb-3">
                            <button
                                type="button"
                                class="fac-ghost text-xs inline-flex items-center gap-2"
                                class:fac-on={draftCurrency.currency === 'USD'}
                                on:click={() => { draftCurrency = { ...draftCurrency, currency: 'USD' }; }}
                            >
                                <CurrencyFlag currency="USD" size={16} />
                                USD
                            </button>
                            <button
                                type="button"
                                class="fac-ghost text-xs inline-flex items-center gap-2"
                                class:fac-on={draftCurrency.currency === 'THB'}
                                on:click={() => { draftCurrency = { ...draftCurrency, currency: 'THB' }; }}
                            >
                                <CurrencyFlag currency="THB" size={16} />
                                THB
                            </button>
                        </div>
                        <div class="flex flex-wrap items-center gap-2 mb-3">
                            <button
                                type="button"
                                class="fac-ghost text-xs"
                                class:fac-on={draftCurrency.rateMode === 'live'}
                                on:click={() => { draftCurrency = { ...draftCurrency, rateMode: 'live' }; }}
                            >
                                Live API
                            </button>
                            <button
                                type="button"
                                class="fac-ghost text-xs"
                                class:fac-on={draftCurrency.rateMode === 'fixed'}
                                on:click={() => { draftCurrency = { ...draftCurrency, rateMode: 'fixed' }; }}
                            >
                                Fixed
                            </button>
                            <input
                                type="number"
                                min="0.01"
                                step="0.01"
                                value={draftCurrency.fixedRate}
                                disabled={draftCurrency.rateMode !== 'fixed'}
                                on:change={(e) => {
                                    const v = parseFloat((e.target as HTMLInputElement).value);
                                    draftCurrency = {
                                        ...draftCurrency,
                                        fixedRate: !Number.isFinite(v) || v <= 0 ? 31 : v
                                    };
                                }}
                                class="w-28 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5] disabled:opacity-50"
                                aria-label="Fixed USD to THB rate"
                            />
                            <span class="text-sm text-[#ececec]">USD → THB</span>
                        </div>
                        <div class="flex flex-wrap items-center gap-2 mb-3">
                            <span class="text-sm text-[#ececec]">Live buffer</span>
                            <input
                                type="number"
                                min="0"
                                step="0.01"
                                value={draftCurrency.liveBuffer}
                                disabled={draftCurrency.rateMode !== 'live'}
                                on:change={(e) => {
                                    const v = parseFloat((e.target as HTMLInputElement).value);
                                    draftCurrency = {
                                        ...draftCurrency,
                                        liveBuffer: !Number.isFinite(v) || v < 0 ? 0 : v
                                    };
                                }}
                                class="w-28 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5] disabled:opacity-50"
                                aria-label="Live rate buffer subtracted from USD to THB"
                            />
                            <span class="text-sm text-[#ececec]">subtracted from live rate</span>
                        </div>
                        <p class="text-xs text-[#ececec]">
                            Default display is USD. Account values stay stored in USD; the dashboard converts for viewing.
                            {#if draftCurrency.rateMode === 'live'}
                                Live rate uses Frankfurter (no signup), with open.er-api as fallback.
                                Buffer {formatNumber(draftCurrency.liveBuffer, false)} turns the mode into {draftCurrency.liveBuffer > 0 ? 'live+buffer' : 'live'}.
                                {#if fxQuote.currency === 'THB' && fxQuote.mode === 'live'}
                                    Current: {formatNumber(fxQuote.rawRate, false)} − {formatNumber(fxQuote.buffer, false)} = {formatNumber(fxQuote.rate, false)} ({fxQuote.source}).
                                {/if}
                            {:else}
                                Fixed rate default is 31.
                            {/if}
                        </p>
                    </fieldset>
                </div>
                <div>
                    <fieldset>
                        <legend class="block text-sm font-medium text-[#f5f5f5] mb-2">Unit Settings</legend>
                        <div class="space-y-2 mb-3">
                            {#each settingsUnitList as unit}
                                <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-2 bg-stone-700/50 border border-stone-600 px-3 py-2">
                                    <div class="flex flex-wrap items-center gap-2">
                                        <span class="text-sm font-medium text-[#ececec]">Unit {unit}</span>
                                        <input
                                            type="text"
                                            value={draftMappings[unit] ?? ''}
                                            placeholder="Name"
                                            on:change={(e) => {
                                                const v = (e.target as HTMLInputElement).value.trim();
                                                draftMappings = { ...draftMappings, [unit]: v };
                                            }}
                                            class="w-36 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
                                        />
                                        <input
                                            type="number"
                                            min="0"
                                            step="100"
                                            value={draftCapitals[unit] ?? 0}
                                            on:change={(e) => {
                                                const v = parseFloat((e.target as HTMLInputElement).value);
                                                draftCapitals = { ...draftCapitals, [unit]: isNaN(v) || v < 0 ? 0 : v };
                                            }}
                                            class="w-32 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
                                        />
                                        <span class="text-sm text-[#ececec]">USD</span>
                                        <span class="text-sm text-[#ececec]">/ Warn %</span>
                                        <input
                                            type="number"
                                            min="1"
                                            max="100"
                                            step="1"
                                            value={draftWarns[unit] ?? 30}
                                            on:change={(e) => {
                                                const v = parseFloat((e.target as HTMLInputElement).value);
                                                const pct = isNaN(v) || v < 1 || v > 100 ? 30 : v;
                                                draftWarns = { ...draftWarns, [unit]: pct };
                                            }}
                                            class="w-20 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
                                        />
                                        <span class="text-sm text-[#ececec]">%</span>
                                    </div>
                                    <button
                                        on:click={() => removeUnitSetting(unit)}
                                        class="fac-minus"
                                        aria-label={`Remove unit settings for unit ${unit}`}
                                    >
                                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                        </svg>
                                    </button>
                                </div>
                            {/each}
                        </div>

                        <div class="flex flex-wrap items-center gap-2">
                            <input type="number" bind:value={newUnitSettingNumber} placeholder="Unit #" min="1" class="w-20 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-center focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]" />
                            <input type="text" bind:value={newUnitSettingName} placeholder="Name" class="w-36 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]" />
                            <input type="number" bind:value={newUnitSettingCap} placeholder="Initial Capital" min="0" step="100" class="w-32 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]" />
                            <span class="text-[#ececec]">USD</span>
                            <span class="text-[#ececec]">/ Warn %</span>
                            <input type="number" bind:value={newUnitSettingWarn} placeholder="%" min="1" max="100" step="1" class="w-20 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]" />
                            <button
                                on:click={addUnitSetting}
                                class="fac-ghost text-xs"
                                disabled={!newUnitSettingNumber || newUnitSettingCap === '' || newUnitSettingWarn === ''}
                            >
                                Add
                            </button>
                        </div>
                        <p class="text-xs text-[#ececec] mt-1">Name, capital, and warning % sit on one row. Changes apply only when you press Save.</p>
                    </fieldset>
                </div>

				<!-- Unit-Specific Broker Min Margin Settings -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2">
							Unit-Specific Broker Min Margin
						</legend>
						<div class="space-y-3 mb-3">
							{#each Object.entries(draftBrokerMargins) as [unitStr, brokerMargins]}
								{@const unit = parseInt(unitStr)}
								<div class="bg-stone-700/50 border border-stone-600">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-[#f5f5f5]">Unit {unit} ({getDraftUnitDisplayName(unit)})</span>
										<span class="text-xs text-[#ececec]">{Object.keys(brokerMargins).length} brokers</span>
									</div>
									<div class="divide-y divide-stone-600">
										{#each Object.entries(brokerMargins) as [brokerName, margin]}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="flex items-center space-x-2 flex-1">
													<input
														type="text"
														value={brokerName}
														on:change={(e) => {
															const newName = (e.target as HTMLInputElement).value.trim();
															if (newName && newName !== brokerName) {
																updateUnitBrokerMargin(unit, brokerName, newName, margin);
															}
														}}
														class="bg-stone-700 border border-stone-600 text-[#f5f5f5] rounded-lg px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5] min-w-0 flex-1"
													/>
						<span class="text-[#ececec]">=</span>
						<input
														type="number"
														min="0"
														step="100"
														value={margin}
														on:change={(e) => {
															const parsed = parseFloat((e.target as HTMLInputElement).value);
															const value = isNaN(parsed) || parsed < 0 ? 0 : parsed;
															updateUnitBrokerMargin(unit, brokerName, brokerName, value);
														}}
														class="w-24 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-lg px-2 py-1 text-right text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
													/>
													<span class="text-xs text-[#ececec]">USD</span>
												</div>
												<button
													on:click={() => removeUnitBrokerMinMargin(unit, brokerName)}
													class="fac-minus hover:fac-minus transition-colors ml-2"
													aria-label={`Remove broker ${brokerName} from unit ${unit}`}
												>
													<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
														<path
															stroke-linecap="round"
															stroke-linejoin="round"
															stroke-width="2"
															d="M6 18L18 6M6 6l12 12"
														/>
													</svg>
												</button>
											</div>
										{/each}
									</div>
								</div>
							{/each}
							{#if Object.keys(draftBrokerMargins).length === 0}
								<div class="text-xs text-[#ececec]">No unit-specific broker margins configured.</div>
							{/if}
						</div>
						<div class="flex flex-wrap items-center gap-2">
							<input
								type="number"
								bind:value={newUnitBrokerUnit}
								placeholder="Unit #"
								min="1"
								class="w-20 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-lg px-2 py-1 text-center focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
							/>
							<span class="text-[#ececec]">→</span>
							<input
								type="text"
								bind:value={newUnitBrokerName}
								placeholder="Broker name"
								class="flex-1 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-lg px-2 py-1 focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
							/>
							<span class="text-[#ececec]">=</span>
							<input
								type="number"
								bind:value={newUnitBrokerMargin}
								placeholder="Min margin"
								min="0"
								step="100"
								class="w-32 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
							/>
							<button
								on:click={addUnitBrokerMinMargin}
								disabled={!newUnitBrokerUnit || !newUnitBrokerName.trim() || !newUnitBrokerMargin}
								class="fac-ghost min-h-11 px-3 rounded-lg text-sm transition-colors"
							>
								Add
							</button>
						</div>
						<p class="text-xs text-[#ececec] mt-1">
							Set minimum margin per broker per unit. Broker names are case-insensitive. You can edit broker names directly by clicking on them.
						</p>
					</fieldset>
				</div>


				<!-- WD Notes Setting (per account) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2"> WD Notes </legend>
						<p class="text-xs text-[#ececec] mb-2">
							Waiting withdrawal per account. Remove here is draft-only until Save.
						</p>
						<div class="space-y-3 max-h-64 overflow-y-auto pr-1">
							{#each Object.entries(draftWdByUnit || {}) as [uStr, entries]}
								{@const u = parseInt(uStr)}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-[#f5f5f5]">Unit {u === 0 ? 'Unknown' : u}</span>
										<span class="text-xs text-[#ececec]"
											>WD Total: {formatNumber(
												(entries || []).reduce((s, e) => s + (e.amount ?? 0), 0),
												false
											)}</span>
										>
									</div>
									<div class="divide-y divide-stone-600/50">
										{#each entries as e}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="text-xs text-[#ececec] truncate mr-2">
													<span class="font-mono">{e.account_number}</span>
													{#if accountByNumber[e.account_number]}
														<span class="text-[#ececec]">
															— {shortName(accountByNumber[e.account_number].account_name)}</span
														>
													{/if}
												</div>
												<div class="flex items-center gap-2">
													<span class="text-xs text-[#ececec]">{formatNumber(e.amount, false)}</span>
													<button
														on:click={() => {
															draftWithdrawals = { ...draftWithdrawals, [e.account_number]: 0 };
														}}
														class="fac-minus hover:fac-minus transition-colors"
														aria-label={`Remove WD for ${e.account_number}`}
													>
														<svg
															class="w-4 h-4"
															fill="none"
															stroke="currentColor"
															viewBox="0 0 24 24"
														>
															<path
																stroke-linecap="round"
																stroke-linejoin="round"
																stroke-width="2"
																d="M6 18L18 6M6 6l12 12"
															/>
														</svg>
													</button>
												</div>
											</div>
										{/each}
									</div>
								</div>
							{/each}
							{#if Object.keys(draftWdByUnit || {}).length === 0}
								<div class="text-xs text-[#ececec]">No non-zero WD notes.</div>
							{/if}
						</div>
						<p class="text-xs text-[#ececec] mt-1">
							Stored as mapping: account_number → amount (grouped by unit for display).
						</p>
					</fieldset>
				</div>

				<!-- DP Notes Setting (per account) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2"> DP Notes </legend>
						<p class="text-xs text-[#ececec] mb-2">
							Deposit adjustment per account. Remove here is draft-only until Save.
						</p>
						<div class="space-y-3 max-h-64 overflow-y-auto pr-1">
							{#each Object.entries(draftDpByUnit || {}) as [uStr, entries]}
								{@const u = parseInt(uStr)}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-[#f5f5f5]">Unit {u === 0 ? 'Unknown' : u}</span>
										<span class="text-xs text-[#ececec]"
											>DP Total: {formatNumber(
												(entries || []).reduce((s, e) => s + (e.amount ?? 0), 0),
												false
											)}</span>
										>
									</div>
									<div class="divide-y divide-stone-600/50">
										{#each entries as e}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="text-xs text-[#ececec] truncate mr-2">
													<span class="font-mono">{e.account_number}</span>
													{#if accountByNumber[e.account_number]}
														<span class="text-[#ececec]">
															— {shortName(accountByNumber[e.account_number].account_name)}</span
														>
													{/if}
												</div>
												<div class="flex items-center gap-2">
													<span class="text-xs text-[#ececec]">{formatNumber(e.amount, false)}</span>
													<button
														on:click={() => {
															draftDeposits = { ...draftDeposits, [e.account_number]: 0 };
														}}
														class="fac-minus hover:fac-minus transition-colors"
														aria-label="Remove DP for {e.account_number}"
													>
														<svg
															class="w-4 h-4"
															fill="none"
															stroke="currentColor"
															viewBox="0 0 24 24"
														>
															<path
																stroke-linecap="round"
																stroke-linejoin="round"
																stroke-width="2"
																d="M6 18L18 6M6 6l12 12"
															/>
														</svg>
													</button>
												</div>
											</div>
										{/each}
									</div>
								</div>
							{/each}
							{#if Object.keys(draftDpByUnit || {}).length === 0}
								<div class="text-xs text-[#ececec]">No non-zero DP notes.</div>
							{/if}
						</div>
						<p class="text-xs text-[#ececec] mt-1">
							Stored as mapping: account_number → amount (grouped by unit for display).
						</p>
					</fieldset>
				</div>

				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2">P/L Alerts</legend>
						<p class="text-xs text-[#ececec] mb-3">
							Email when adjusted P/L crosses a threshold. Each alert sends once, then stays paused until you reset it.
						</p>
						<div class="space-y-3">
							<div class="flex flex-wrap items-center gap-2 text-sm text-[#ececec]">
								<label class="inline-flex items-center gap-2">
									<input
										type="checkbox"
										checked={draftPlAlert.profitEnabled}
										on:change={(e) => {
											draftPlAlert = { ...draftPlAlert, profitEnabled: (e.target as HTMLInputElement).checked };
										}}
										class="border-stone-600 bg-stone-700 text-[#f5f5f5] focus:ring-[#f5f5f5]"
									/>
									<span>Profit alert</span>
								</label>
								<input
									type="number"
									min="0"
									step="100"
									value={draftPlAlert.profitThreshold}
									on:change={(e) => {
										const v = parseFloat((e.target as HTMLInputElement).value);
										draftPlAlert = { ...draftPlAlert, profitThreshold: isNaN(v) || v < 0 ? 0 : v };
									}}
									class="w-32 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
								/>
								<span>USD</span>
							</div>
							<div class="flex flex-wrap items-center gap-2 text-sm text-[#ececec]">
								<label class="inline-flex items-center gap-2">
									<input
										type="checkbox"
										checked={draftPlAlert.lossEnabled}
										on:change={(e) => {
											draftPlAlert = { ...draftPlAlert, lossEnabled: (e.target as HTMLInputElement).checked };
										}}
										class="border-stone-600 bg-stone-700 text-[#f5f5f5] focus:ring-[#f5f5f5]"
									/>
									<span>Loss alert</span>
								</label>
								<input
									type="number"
									min="0"
									step="100"
									value={draftPlAlert.lossThreshold}
									on:change={(e) => {
										const v = parseFloat((e.target as HTMLInputElement).value);
										draftPlAlert = { ...draftPlAlert, lossThreshold: isNaN(v) || v < 0 ? 0 : v };
									}}
									class="w-32 border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 text-right focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
								/>
								<span>USD</span>
							</div>
							<label class="block text-sm text-[#ececec]">
								<span class="block mb-1">Recipient email</span>
								<input
									type="email"
									value={draftPlAlert.recipientEmail}
									placeholder="alerts@example.com"
									on:change={(e) => {
										draftPlAlert = { ...draftPlAlert, recipientEmail: (e.target as HTMLInputElement).value.trim() };
									}}
									class="w-full max-w-md border border-stone-600 bg-stone-700 text-[#f5f5f5] px-2 py-1 focus:ring-2 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
								/>
							</label>
						</div>
					</fieldset>
				</div>

				<!-- Delete Account Data Section -->
				<div class="border-t border-stone-700 pt-6">
					<fieldset>
						<legend class="block text-sm font-medium text-red-600 mb-2">
							Danger Zone
						</legend>
						<div class="bg-red-900/20 border border-red-800/40 rounded-xl p-4">
							<div class="flex items-start space-x-3">
								<svg class="w-5 h-5 fac-minus mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
								</svg>
								<div class="flex-1">
									<h4 class="text-sm font-medium fac-minus mb-1">ลบข้อมูลบัญชีทั้งหมด</h4>
									<p class="text-xs fac-minus mb-3">
										การดำเนินการนี้จะลบข้อมูลบัญชีทั้งหมดจาก Supabase แต่จะไม่ลบการตั้งค่าอื่นๆ เช่น Initial Capital, Unit Mappings เป็นต้น
									</p>
									<button
										on:click={() => (showDeleteConfirmModal = true)}
										class="px-3 py-1.5 rounded-lg bg-red-500 hover:bg-red-600 text-white text-sm font-medium transition-colors"
									>
										ลบข้อมูลบัญชีทั้งหมด
									</button>
								</div>
							</div>
						</div>
					</fieldset>
				</div>
			</div>

			<div
				class="px-4 sm:px-6 py-3 sm:py-4 border-t border-[#f5f5f5] flex items-center justify-end gap-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]"
			>
				<button
					on:click={closeSettings}
					class="fac-ghost flex-1 sm:flex-none"
				>
					Cancel
				</button>
				<button
					on:click={saveSettings}
					disabled={savingSettings}
					class="fac-ghost flex-1 sm:flex-none"
				>
					{savingSettings ? 'Saving...' : 'Save'}
				</button>
			</div>
		</div>
	</div>
{/if}

<!-- Delete Confirmation Modal -->
{#if showDeleteConfirmModal}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-60 flex items-center justify-center p-4 sm:p-6"
		on:click={() => (showDeleteConfirmModal = false)}
		on:keydown={(e) => e.key === 'Escape' && (showDeleteConfirmModal = false)}
		role="dialog"
		aria-modal="true"
		aria-labelledby="delete-confirm-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] border border-[#ff4d4d] w-full max-w-md mx-4 p-2"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6">
				<div class="flex items-center mb-4">
					<div class="w-12 h-12 border border-[#ff4d4d] flex items-center justify-center mr-4">
						<svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
						</svg>
					</div>
					<div>
						<h3 id="delete-confirm-title" class="text-lg font-semibold text-[#f5f5f5]">ยืนยันการลบข้อมูล</h3>
						<p class="text-sm text-[#ececec]">การดำเนินการนี้ไม่สามารถย้อนกลับได้</p>
					</div>
				</div>

				<div class="mb-6">
					<p class="text-sm text-[#ececec] mb-3">
						คุณแน่ใจหรือไม่ที่จะลบข้อมูลบัญชีทั้งหมดจาก Supabase?
					</p>
					<div class="border border-[#ff4d4d] p-3">
						<p class="text-xs text-red-300">
							<strong>หมายเหตุ:</strong> การดำเนินการนี้จะลบเฉพาะข้อมูลบัญชีที่เข้ามาจาก EA เท่านั้น 
							การตั้งค่าอื่นๆ เช่น Initial Capital, Unit Mappings, WD Notes, DP Notes จะไม่ถูกลบ
						</p>
					</div>
				</div>

				<div class="flex items-center justify-end gap-3">
					<button
						on:click={() => (showDeleteConfirmModal = false)}
						class="min-h-11 flex-1 sm:flex-none px-4 py-2 rounded-xl bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 transition-colors"
						disabled={deletingData}
					>
						ยกเลิก
					</button>
					<button
						on:click={clearAllAccountData}
						disabled={deletingData}
						class="min-h-11 flex-1 sm:flex-none px-4 py-2 rounded-xl bg-red-500 text-white hover:bg-red-600 disabled:bg-stone-700 disabled:text-[#ececec] disabled:cursor-not-allowed transition-colors flex items-center justify-center gap-2"
					>
						{#if deletingData}
							<svg class="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
								<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
								<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
							</svg>
							กำลังลบ...
						{:else}
							ลบข้อมูลทั้งหมด
						{/if}
					</button>
				</div>
			</div>
		</div>
	</div>
{/if}
