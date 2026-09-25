<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import type { AccountSummary, CurrencySettings, DashboardStats, EquityWarningState, ExternalWallet, FxQuote, OrderInfo, PendingWithdrawal, PlAlertSettings, PlAlertState } from '$lib/types.js';
	import { EXTERNAL_WALLET_NAME_MAX, defaultExternalWallet, normalizeExternalWallet, roundMoney } from '$lib/external-wallet-model.js';
	import { PENDING_NOTE_MAX_LENGTH } from '$lib/pending-withdrawal-model.js';
	import { defaultPlAlertSettings, defaultPlAlertState } from '$lib/pl-alert-model.js';
	import {
		defaultEquityWarningState,
		getUnitTargetEquity as targetEquityFromCap,
		getUnitWarningPct as warnPctFromValue,
		equityMeter,
		getWarningThreshold,
		isEquityWarningPaused,
		isLowEquityWarning as isLowEquityByValues,
		normalizeEquityWarningState
	} from '$lib/equity-warning-model.js';
	import { convertUsd, defaultCurrencySettings, identityFxQuote, normalizeCurrencySettings } from '$lib/currency.js';
	import CurrencyFlag from '$lib/CurrencyFlag.svelte';
	import {
		computeUnitDelta,
		computeUnitPairs,
		listUnitDiffLanes,
		type PairInfo
	} from '$lib/pairs.js';

	let stats: DashboardStats = {
		total_balance: 0,
		profit_loss: 0,
		initial_capital: 0,
		account_count: 0
	};
	let summaries: AccountSummary[] = [];
    let initialCapital = 0;
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
	let unitDeposits: Record<number, number> = {};
	let externalWallet: ExternalWallet = defaultExternalWallet();
	let settingsWalletCredit = 0;
	let walletPrompt: { kind: 'dp-note' | 'settings-dp'; unit: number; previous: number; next: number } | null = null;
	let walletPromptSaving = false;
	let walletNameEditing = false;
	let walletNameDraft = '';
	let walletAdjustOpen = false;
	let walletAdjustValue = '';
	let walletAdjustSaving = false;
	let pendingWithdrawals: PendingWithdrawal[] = [];
	let pendingDialogAccount: AccountSummary | null = null;
	let pendingAmount = '';
	let pendingNote = '';
	let pendingDate = '';
	let pendingFormError = '';
	let pendingSaving = false;
	let pendingDeleteTarget: PendingWithdrawal | null = null;
	let pendingDeleting = false;
	let noteAdd: { unit: number; side: 'wd' | 'dp' } | null = null;
	let noteAddAmount = '';
	let noteAddSaving = false;
	let noteAddError = '';
	let noteAddInput: HTMLInputElement | null = null;
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
	let equityWarningState: EquityWarningState = defaultEquityWarningState();
	let currencySettings: CurrencySettings = defaultCurrencySettings();
	let draftCurrency: CurrencySettings = defaultCurrencySettings();
	let fxQuote: FxQuote = identityFxQuote(defaultCurrencySettings());
	let resettingAlert: 'profit' | 'loss' | null = null;
	let resettingEquityUnit: number | null = null;
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
	const SHOW_USD_EQUIV_KEY = 'pm-show-usd-equiv';
	function readStoredShowUsdEquiv(): boolean {
		try {
			return sessionStorage.getItem(SHOW_USD_EQUIV_KEY) !== '0';
		} catch {
			return true;
		}
	}
	let showUsdEquiv = typeof sessionStorage !== 'undefined' ? readStoredShowUsdEquiv() : true;
	function setShowUsdEquiv(next: boolean) {
		showUsdEquiv = next;
		try {
			sessionStorage.setItem(SHOW_USD_EQUIV_KEY, next ? '1' : '0');
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
	let draftWithdrawals: Record<number, number> = {};
	let draftDeposits: Record<number, number> = {};

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
		draftWithdrawals = { ...unitWithdrawals };
		draftDeposits = { ...unitDeposits };
		settingsWalletCredit = 0;
		if (walletPrompt?.kind === 'settings-dp') walletPrompt = null;
		draftPlAlert = { ...plAlertSettings };
		draftCurrency = { ...currencySettings };
		showSettingsModal = true;
	}

	function closeSettings() {
		settingsWalletCredit = 0;
		if (walletPrompt?.kind === 'settings-dp') walletPrompt = null;
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
    $: totalWaitingWD = Object.values(unitWithdrawals || {}).reduce(
		(sum, v) => sum + (typeof v === 'number' ? v : 0),
		0
	);

	$: totalDeposits = Object.values(unitDeposits || {}).reduce(
		(sum, v) => sum + (typeof v === 'number' ? v : 0),
		0
	);
	$: adjustedProfitLoss = (stats?.profit_loss || 0) + (totalWaitingWD || 0) - (totalDeposits || 0);
	$: adjustedProfitLossPercent =
		initialCapital > 0 ? (adjustedProfitLoss / initialCapital) * 100 : 0;

	// Snapshot data returned from server
	let snapshot: { value: number; kind: 'adjusted' | 'real'; timestamp: string } | null = null;
	let snapshotDelta: number | null = null;
	$: heroValue = snapshot ? (snapshotDelta ?? 0) : adjustedProfitLoss;
	$: heroAmountShown = bookValue(
		(heroValue >= 0.005 ? '+' : '') + formatNumber(heroValue),
		true
	);
	$: heroAmountParts = splitAmount(heroAmountShown);

	let unitPairsMap: Record<number, { pairs: PairInfo[]; unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> }> = {};

	$: unitPairsMap = Object.entries(unitGroups || {}).reduce(
		(acc, [unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			acc[unit] = computeUnitPairs(accounts);
			return acc;
		},
		{} as Record<number, { pairs: PairInfo[]; unmatched: Array<OrderInfo & { account_number: string; broker_name: string }> }>
	);

	$: diffLanes = listUnitDiffLanes(unitGroups, unitInitialCapitals, unitWarningEquityPercentages);

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
				unitWithdrawals = data.unitWithdrawals || {};
				unitDeposits = data.unitDeposits || {};
				if (data.externalWallet) externalWallet = normalizeExternalWallet(data.externalWallet);
				pendingWithdrawals = Array.isArray(data.pendingWithdrawals) ? data.pendingWithdrawals : [];
				latestUpdate = (summaries || []).reduce((latest, a) => {
					const t = new Date(a.last_update).getTime();
					return t > latest ? t : latest;
				}, 0);
				snapshot = data.snapshot || null;
				snapshotDelta = data.snapshotDelta ?? null;
				if (data.plAlert?.settings) plAlertSettings = data.plAlert.settings;
				if (data.plAlert?.state) plAlertState = data.plAlert.state;
				if (data.equityWarning?.state) equityWarningState = normalizeEquityWarningState(data.equityWarning.state);
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
			unitDeposits = data.unit_deposits || {};
			if (data.external_wallet) externalWallet = normalizeExternalWallet(data.external_wallet);
			plAlertSettings = data.pl_alert || defaultPlAlertSettings();
			plAlertState = data.pl_alert_state || defaultPlAlertState();
			equityWarningState = normalizeEquityWarningState(data.equity_warning_state);
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

	function parseNoteInput(event: Event): number {
		const input = event.target as HTMLInputElement;
		const raw = input.value.trim();
		const parsed = parseFloat(raw);
		if (!raw || isNaN(parsed) || parsed < 0) return 0;
		return Math.round(parsed * 100) / 100;
	}

	function unitNoteAmount(notes: Record<number, number>, unit: number): number {
		const value = notes?.[unit];
		return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0;
	}

	async function saveUnitNotes(): Promise<boolean> {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					unit_withdrawals: unitWithdrawals,
					unit_deposits: unitDeposits
				})
			});

			if (response.ok) {
				const data = await response.json();
				unitWithdrawals = data.unit_withdrawals || {};
				unitDeposits = data.unit_deposits || {};
				if (data.external_wallet) externalWallet = normalizeExternalWallet(data.external_wallet);
				await fetchData();
				return true;
			}
		} catch (error) {
			console.error('Error updating unit notes:', error);
		}
		return false;
	}

	async function saveExternalWallet() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ external_wallet: externalWallet })
			});
			if (response.ok) {
				const data = await response.json();
				externalWallet = normalizeExternalWallet(data.external_wallet);
				await fetchData();
			}
		} catch (error) {
			console.error('Error updating external wallet:', error);
		}
	}

	function walletEffect(previous: number, next: number): number {
		return roundMoney(previous - next);
	}

	function handleUnitWithdrawalChange(unit: number, event: Event) {
		unitWithdrawals = { ...unitWithdrawals, [unit]: parseNoteInput(event) };
		void saveUnitNotes();
	}

	async function handleUnitDepositChange(unit: number, event: Event) {
		const previous = unitNoteAmount(unitDeposits, unit);
		const next = parseNoteInput(event);
		if (next === previous) return;
		unitDeposits = { ...unitDeposits, [unit]: next };
		const saved = await saveUnitNotes();
		if (!saved || next === previous) return;
		walletPrompt = { kind: 'dp-note', unit, previous, next };
	}

	function parseNoteAddAmount(raw: string | number): number {
		const text = String(raw ?? '').trim();
		const parsed = parseFloat(text);
		if (!text || !Number.isFinite(parsed) || parsed <= 0) return 0;
		return roundMoney(parsed);
	}

	async function openNoteAdd(unit: number, side: 'wd' | 'dp') {
		noteAdd = { unit, side };
		noteAddAmount = '';
		noteAddError = '';
		await tick();
		noteAddInput?.focus();
	}

	function closeNoteAdd() {
		if (noteAddSaving) return;
		noteAdd = null;
		noteAddAmount = '';
		noteAddError = '';
	}

	$: noteAddCurrent = noteAdd
		? unitNoteAmount(noteAdd.side === 'wd' ? unitWithdrawals : unitDeposits, noteAdd.unit)
		: 0;
	$: noteAddDelta = parseNoteAddAmount(noteAddAmount);
	$: noteAddNext = roundMoney(noteAddCurrent + noteAddDelta);

	async function submitNoteAdd() {
		if (!noteAdd || noteAddSaving) return;
		const delta = parseNoteAddAmount(noteAddAmount);
		if (delta <= 0) {
			noteAddError = 'Enter an amount greater than 0';
			return;
		}
		const { unit, side } = noteAdd;
		const previous = unitNoteAmount(side === 'wd' ? unitWithdrawals : unitDeposits, unit);
		const next = roundMoney(previous + delta);
		noteAddSaving = true;
		noteAddError = '';
		if (side === 'wd') {
			unitWithdrawals = { ...unitWithdrawals, [unit]: next };
		} else {
			unitDeposits = { ...unitDeposits, [unit]: next };
		}
		const saved = await saveUnitNotes();
		noteAddSaving = false;
		if (!saved) {
			if (side === 'wd') {
				unitWithdrawals = { ...unitWithdrawals, [unit]: previous };
			} else {
				unitDeposits = { ...unitDeposits, [unit]: previous };
			}
			noteAddError = 'Could not save';
			return;
		}
		noteAdd = null;
		noteAddAmount = '';
		if (side === 'dp' && next !== previous) {
			walletPrompt = { kind: 'dp-note', unit, previous, next };
		}
	}

	function requestSettingsDpClear(unit: number) {
		const previous = unitNoteAmount(draftDeposits, unit);
		if (previous <= 0) return;
		walletPrompt = { kind: 'settings-dp', unit, previous, next: 0 };
	}

	function dismissWalletPrompt() {
		if (walletPromptSaving) return;
		walletPrompt = null;
	}

	async function confirmWalletPrompt(applyToWallet: boolean) {
		if (!walletPrompt || walletPromptSaving) return;
		const prompt = walletPrompt;
		const effect = walletEffect(prompt.previous, prompt.next);
		if (prompt.kind === 'settings-dp') {
			draftDeposits = { ...draftDeposits, [prompt.unit]: 0 };
			if (applyToWallet) settingsWalletCredit = roundMoney(settingsWalletCredit + effect);
			walletPrompt = null;
			return;
		}
		walletPrompt = null;
		if (!applyToWallet || effect === 0) return;
		walletPromptSaving = true;
		externalWallet = {
			...externalWallet,
			balance: roundMoney(externalWallet.balance + effect),
			updated_at: new Date().toISOString()
		};
		await saveExternalWallet();
		walletPromptSaving = false;
	}

	function startWalletNameEdit() {
		walletNameDraft = externalWallet.name;
		walletNameEditing = true;
	}

	function cancelWalletNameEdit() {
		walletNameEditing = false;
		walletNameDraft = '';
	}

	function commitWalletName() {
		const name = walletNameDraft.trim().slice(0, EXTERNAL_WALLET_NAME_MAX) || 'Wallet';
		walletNameEditing = false;
		walletNameDraft = '';
		if (name === externalWallet.name) return;
		externalWallet = { ...externalWallet, name };
		void saveExternalWallet();
	}

	function openWalletAdjust() {
		walletAdjustValue = String(externalWallet.balance);
		walletAdjustOpen = true;
	}

	function closeWalletAdjust() {
		if (walletAdjustSaving) return;
		walletAdjustOpen = false;
	}

	async function applyWalletAdjust() {
		if (walletAdjustSaving) return;
		const parsed = parseFloat(walletAdjustValue);
		if (!Number.isFinite(parsed)) return;
		walletAdjustSaving = true;
		externalWallet = {
			...externalWallet,
			balance: roundMoney(parsed),
			updated_at: new Date().toISOString()
		};
		await saveExternalWallet();
		walletAdjustSaving = false;
		walletAdjustOpen = false;
	}

	let adjustingPLUnits: Set<number> = new Set();
	let adjustingAllPL = false;

	async function adjustUnitPLToZero(unit: number) {
		const stat = unitStats.find((s) => s.unit === unit);
		if (!stat || Math.abs(stat.profitLoss) < 0.01) return;
		if ((unitGroups[unit] || []).length === 0) return;

		const direction = stat.profitLoss > 0 ? 'DP Note' : 'WD Note';
		const amount = Math.abs(Math.round(stat.profitLoss * 100) / 100);
		if (!confirm(`Zero P/L for Unit ${unit}?\n\nP/L: ${moneyLine(stat.profitLoss, '', true)}\nWill add ${moneyLine(amount, '', true)} to this group's ${direction}`)) return;

		adjustingPLUnits = new Set([...adjustingPLUnits, unit]);
		const pl = Math.round(stat.profitLoss * 100) / 100;
		if (pl > 0) {
			unitDeposits = {
				...unitDeposits,
				[unit]: Math.round((unitNoteAmount(unitDeposits, unit) + pl) * 100) / 100
			};
		} else {
			unitWithdrawals = {
				...unitWithdrawals,
				[unit]: Math.round((unitNoteAmount(unitWithdrawals, unit) + Math.abs(pl)) * 100) / 100
			};
		}
		await saveUnitNotes();
		adjustingPLUnits = new Set([...adjustingPLUnits].filter((u) => u !== unit));
	}

	async function adjustAllGroupsPL() {
		const affectedUnits = unitStats.filter((s) => Math.abs(s.profitLoss) >= 0.01 && (unitGroups[s.unit] || []).length > 0);
		if (affectedUnits.length === 0) return;

		const summary = affectedUnits.map((s) => `  Unit ${s.unit}: P/L ${moneyLine(s.profitLoss, s.profitLoss >= 0 ? '+' : '', true)}`).join('\n');
		if (!confirm(`Zero P/L for all groups?\n\n${summary}\n\nThis will adjust each group's WD/DP Note.`)) return;

		adjustingAllPL = true;
		const nextWD = { ...unitWithdrawals };
		const nextDP = { ...unitDeposits };
		for (const stat of affectedUnits) {
			const pl = Math.round(stat.profitLoss * 100) / 100;
			if (pl > 0) {
				nextDP[stat.unit] = Math.round((unitNoteAmount(nextDP, stat.unit) + pl) * 100) / 100;
			} else if (pl < 0) {
				nextWD[stat.unit] = Math.round((unitNoteAmount(nextWD, stat.unit) + Math.abs(pl)) * 100) / 100;
			}
		}
		unitWithdrawals = nextWD;
		unitDeposits = nextDP;
		await saveUnitNotes();
		adjustingAllPL = false;
	}

	let consolidatingUnits: Set<number> = new Set();
	let consolidatingAll = false;

	function unitNoteNet(unit: number, withdrawals = unitWithdrawals, deposits = unitDeposits) {
		const totalWD = unitNoteAmount(withdrawals, unit);
		const totalDP = unitNoteAmount(deposits, unit);
		return {
			totalWD,
			totalDP,
			net: Math.round((totalWD - totalDP) * 100) / 100
		};
	}

	function isUnitNotNetted(unit: number, withdrawals = unitWithdrawals, deposits = unitDeposits): boolean {
		const { totalWD, totalDP } = unitNoteNet(unit, withdrawals, deposits);
		return totalWD > 0 && totalDP > 0;
	}

	function applyUnitNet(unit: number, withdrawals: Record<number, number>, deposits: Record<number, number>) {
		const { net } = unitNoteNet(unit, withdrawals, deposits);
		withdrawals[unit] = net > 0 ? net : 0;
		deposits[unit] = net < 0 ? Math.abs(net) : 0;
	}

	async function consolidateGroupWDDP(unit: number) {
		if ((unitGroups[unit] || []).length === 0 || !isUnitNotNetted(unit)) return;
		const { totalWD, totalDP, net } = unitNoteNet(unit);
		const resultLine = net > 0
			? `Net WD: ${moneyLine(net, '', true)}`
			: net < 0
				? `Net DP: ${moneyLine(Math.abs(net), '', true)}`
				: 'Net: 0 (both cleared)';
		if (!confirm(`Simplify WD/DP for Unit ${unit}?\n\nWD: ${moneyLine(totalWD, '', true)}\nDP: ${moneyLine(totalDP, '', true)}\n\nResult:\n  ${resultLine}`)) return;

		consolidatingUnits = new Set([...consolidatingUnits, unit]);
		const nextWD = { ...unitWithdrawals };
		const nextDP = { ...unitDeposits };
		applyUnitNet(unit, nextWD, nextDP);
		unitWithdrawals = nextWD;
		unitDeposits = nextDP;
		await saveUnitNotes();
		consolidatingUnits = new Set([...consolidatingUnits].filter((u) => u !== unit));
	}

	async function consolidateAllGroupsWDDP() {
		const groups = Object.keys(unitGroups)
			.map((unitStr) => parseInt(unitStr))
			.filter((unit) => isUnitNotNetted(unit))
			.map((unit) => ({ unit, ...unitNoteNet(unit) }));
		if (groups.length === 0) return;

		const lines = groups.map((g) => `  Unit ${g.unit}: WD ${moneyLine(g.totalWD, '', true)}, DP ${moneyLine(g.totalDP, '', true)} -> Net ${g.net >= 0 ? 'WD' : 'DP'} ${moneyLine(Math.abs(g.net), '', true)}`).join('\n');
		if (!confirm(`Simplify WD/DP for all groups?\n\n${lines}`)) return;

		consolidatingAll = true;
		const nextWD = { ...unitWithdrawals };
		const nextDP = { ...unitDeposits };
		for (const group of groups) applyUnitNet(group.unit, nextWD, nextDP);
		unitWithdrawals = nextWD;
		unitDeposits = nextDP;
		await saveUnitNotes();
		consolidatingAll = false;
	}

	$: settingsNoteUnits = Array.from(new Set([
		...Object.keys(draftWithdrawals || {}),
		...Object.keys(draftDeposits || {})
	]))
		.map((key) => parseInt(key))
		.filter((unit) => !isNaN(unit) && (unitNoteAmount(draftWithdrawals, unit) > 0 || unitNoteAmount(draftDeposits, unit) > 0))
		.sort((a, b) => a - b);

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
        return targetEquityFromCap(unitInitialCapitals[unit] ?? 0);
    }

    function getUnitWarningPct(unit: number): number {
        return warnPctFromValue(unitWarningEquityPercentages[unit]);
    }

    function isLowEquityWarning(account: AccountSummary): boolean {
        return isLowEquityByValues(
            account.latest_equity,
            unitInitialCapitals[account.unit] ?? 0,
            unitWarningEquityPercentages[account.unit]
        );
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

	const MASK = '#####';

	function formatNumber(num: number, convert = true): string {
		const value = convert ? convertUsd(num, displayRate) : num;
		const result = new Intl.NumberFormat('th-TH', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		}).format(value);
		return result === '-0.00' ? '0.00' : result;
	}

	function splitAmount(formatted: string): { whole: string; frac: string } {
		const index = formatted.lastIndexOf('.');
		if (index === -1) return { whole: formatted, frac: '' };
		return { whole: formatted.slice(0, index), frac: formatted.slice(index) };
	}

	$: usdParen = (amount: number, prefix = '', reveal = revealBookValues): string => {
		if (displayCurrency === 'USD' || !showUsdEquiv) return '';
		if (!reveal) return MASK;
		return `(${prefix}${formatNumber(amount, false)} USD)`;
	};

	$: moneyLine = (amount: number, prefix = '', reveal = revealBookValues): string => {
		if (!reveal) return MASK;
		const shown = prefix + formatNumber(amount);
		const extra = usdParen(amount, prefix, true);
		return extra ? `${shown} ${extra}` : shown;
	};

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

	function formatLocalDateTime(dateStr: string): string {
		const d = new Date(dateStr);
		if (Number.isNaN(d.getTime())) return '';
		const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`);
		return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
	}

	function shortName(name: string): string {
		if (!name) return '';
		return name.length > 8 ? name.slice(0, 8) + '~' : name;
	}

	function pendingTotalForAccount(accountNumber: string): number {
		return pendingWithdrawals
			.filter((item) => item.account_number === accountNumber)
			.reduce((sum, item) => sum + item.amount, 0);
	}

	function pendingTotalForAccounts(accounts: AccountSummary[]): number {
		const numbers = new Set(accounts.map((account) => account.account_number));
		return pendingWithdrawals
			.filter((item) => numbers.has(item.account_number))
			.reduce((sum, item) => sum + item.amount, 0);
	}

	function openPendingDialog(account: AccountSummary) {
		pendingDialogAccount = account;
		pendingAmount = '';
		pendingNote = '';
		pendingDate = '';
		pendingFormError = '';
	}

	function closePendingDialog() {
		if (pendingSaving) return;
		pendingDialogAccount = null;
		pendingFormError = '';
	}

	function requestPendingDelete(entry: PendingWithdrawal) {
		pendingDeleteTarget = entry;
	}

	function closePendingDelete() {
		if (pendingDeleting) return;
		pendingDeleteTarget = null;
	}

	async function submitPendingWithdrawal() {
		if (!pendingDialogAccount || pendingSaving) return;
		const amount = Number(pendingAmount);
		if (!Number.isFinite(amount) || amount <= 0) {
			pendingFormError = 'Enter an amount greater than 0';
			return;
		}
		pendingSaving = true;
		pendingFormError = '';
		try {
			const res = await fetch('/api/pending-withdrawals', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					account_number: pendingDialogAccount.account_number,
					amount,
					note: pendingNote,
					withdrawn_at: pendingDate || undefined
				})
			});
			const data = await res.json();
			if (!res.ok) {
				pendingFormError = data.error || 'Failed to save';
				return;
			}
			pendingWithdrawals = Array.isArray(data.pendingWithdrawals) ? data.pendingWithdrawals : [];
			pendingAmount = '';
			pendingNote = '';
			pendingDate = '';
		} catch (error) {
			console.error('Error saving pending withdrawal:', error);
			pendingFormError = 'Failed to save';
		} finally {
			pendingSaving = false;
		}
	}

	async function confirmPendingDelete(addToWallet: boolean) {
		if (!pendingDeleteTarget || pendingDeleting) return;
		const credit = pendingDeleteTarget.amount;
		pendingDeleting = true;
		try {
			const res = await fetch(`/api/pending-withdrawals/${encodeURIComponent(pendingDeleteTarget.id)}`, {
				method: 'DELETE'
			});
			const data = await res.json();
			if (res.ok) {
				pendingWithdrawals = Array.isArray(data.pendingWithdrawals) ? data.pendingWithdrawals : [];
				pendingDeleteTarget = null;
				if (addToWallet) {
					externalWallet = {
						...externalWallet,
						balance: roundMoney(externalWallet.balance + credit),
						updated_at: new Date().toISOString()
					};
					await saveExternalWallet();
				}
			}
		} catch (error) {
			console.error('Error deleting pending withdrawal:', error);
		} finally {
			pendingDeleting = false;
		}
	}

	$: pendingDialogHistory = pendingDialogAccount
		? pendingWithdrawals
				.filter((item) => item.account_number === pendingDialogAccount?.account_number)
				.sort((a, b) => new Date(b.withdrawn_at).getTime() - new Date(a.withdrawn_at).getTime())
		: [];
	$: pendingSummaryRows = [...pendingWithdrawals].sort(
		(a, b) => new Date(b.withdrawn_at).getTime() - new Date(a.withdrawn_at).getTime()
	);

function truncateWithEllipsis(name: string, max: number = 6): string {
    if (!name) return '';
    return name.length > max ? name.slice(0, max) + '...' : name;
}

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
		showUsdEquiv = readStoredShowUsdEquiv();
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
			const settingsBody: Record<string, unknown> = {
                    unit_initial_capitals: draftCapitals,
                    unit_warning_equity_percentages: draftWarns,
					unit_mappings: draftMappings,
					unit_broker_min_margins: draftBrokerMargins,
					unit_withdrawals: draftWithdrawals,
					unit_deposits: draftDeposits,
					pl_alert: draftPlAlert,
					currency: draftCurrency
			};
			if (settingsWalletCredit !== 0) {
				settingsBody.external_wallet = {
					...externalWallet,
					balance: roundMoney(externalWallet.balance + settingsWalletCredit),
					updated_at: new Date().toISOString()
				};
			}
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(settingsBody)
			});
			if (response.ok) {
				const data = await response.json();
                initialCapital = data.initial_capital;
                unitInitialCapitals = data.unit_initial_capitals || draftCapitals;
                unitWarningEquityPercentages = data.unit_warning_equity_percentages || draftWarns;
				unitMappings = data.unit_mappings || draftMappings;
				unitBrokerMinMargins = data.unit_broker_min_margins || draftBrokerMargins;
				unitWithdrawals = data.unit_withdrawals || {};
				unitDeposits = data.unit_deposits || {};
				plAlertSettings = data.pl_alert || draftPlAlert;
				plAlertState = data.pl_alert_state || plAlertState;
				if (data.equity_warning_state) equityWarningState = normalizeEquityWarningState(data.equity_warning_state);
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

	async function resetEquityWarning(unit: number) {
		if (resettingEquityUnit !== null) return;
		resettingEquityUnit = unit;
		await tick();
		try {
			const response = await fetch('/api/alerts/reset', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ kind: 'equity', unit })
			});
			if (response.ok) {
				const data = await response.json();
				if (data.equityWarningState) {
					equityWarningState = normalizeEquityWarningState(data.equityWarningState);
				}
			}
		} catch (error) {
			console.error('Error resetting equity warning:', error);
		} finally {
			resettingEquityUnit = null;
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
				<div class="flex flex-col gap-0.5 text-xs mt-1 min-w-0 sm:flex-row sm:items-center sm:gap-2">
					{#if resumeLoading}
						<span title="Returned to app — fetching latest data">RESUMED · LOADING LATEST</span>
					{:else}
						<div class="flex items-center gap-2 min-w-0">
							{#if latestUpdate}
								<span class="tabular-nums whitespace-nowrap">{formatDateTime(new Date(latestUpdate).toISOString())}</span>
							{/if}
							<span class="tabular-nums shrink-0" title="Next refresh">{String(countdownSeconds).padStart(2, '0')}s</span>
						</div>
						{#if displayCurrency !== 'USD'}
							<span
								class="whitespace-nowrap"
								title={fxQuote.displayMode === 'live+buffer'
									? `USD → ${displayCurrency} @ ${fxQuote.rawRate} − ${fxQuote.buffer} = ${fxQuote.rate} (${fxQuote.source})`
									: `USD → ${displayCurrency} @ ${fxQuote.rate} (${fxQuote.source})`}
							>
								{displayCurrency} · {formatNumber(fxQuote.rate, false)} · {fxQuote.displayMode}
							</span>
						{/if}
					{/if}
				</div>
			</div>
			<div class="flex items-center gap-1.5 shrink-0">
				{#if displayCurrency !== 'USD'}
					<button
						on:click={() => setShowUsdEquiv(!showUsdEquiv)}
						class="fac-ghost fac-icon"
						class:fac-on={!showUsdEquiv}
						title={showUsdEquiv ? 'Hide USD amounts' : 'Show USD amounts'}
						aria-label={showUsdEquiv ? 'Hide USD amounts' : 'Show USD amounts'}
						aria-pressed={!showUsdEquiv}
					>
						<span class="relative text-[10px] font-semibold leading-none tracking-tight">
							USD
							{#if !showUsdEquiv}
								<span class="absolute -left-0.5 -right-0.5 top-1/2 h-px bg-current"></span>
							{/if}
						</span>
					</button>
				{/if}
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
		{#if (plAlertSettings.profitEnabled && plAlertState.profitPaused) || (plAlertSettings.lossEnabled && plAlertState.lossPaused)}
			<div class="max-w-7xl mx-auto px-3 sm:px-4 pb-3 flex flex-col sm:flex-row gap-2">
				{#if plAlertSettings.profitEnabled && plAlertState.profitPaused}
					<button
						on:click={() => resetPlAlert('profit')}
						class="w-full min-h-14 px-4 fac-display text-xl sm:text-2xl font-extrabold tracking-tight bg-[#ffcc33] text-[#0a0a0a] border border-[#ffcc33] hover:bg-[#f5f5f5] hover:border-[#f5f5f5] disabled:opacity-45 disabled:cursor-not-allowed"
						disabled={resettingAlert !== null}
					>
						{resettingAlert === 'profit' ? 'RESETTING...' : 'RESET PROFIT ALERT'}
					</button>
				{/if}
				{#if plAlertSettings.lossEnabled && plAlertState.lossPaused}
					<button
						on:click={() => resetPlAlert('loss')}
						class="w-full min-h-14 px-4 fac-display text-xl sm:text-2xl font-extrabold tracking-tight bg-[#ffcc33] text-[#0a0a0a] border border-[#ffcc33] hover:bg-[#f5f5f5] hover:border-[#f5f5f5] disabled:opacity-45 disabled:cursor-not-allowed"
						disabled={resettingAlert !== null}
					>
						{resettingAlert === 'loss' ? 'RESETTING...' : 'RESET LOSS ALERT'}
					</button>
				{/if}
			</div>
		{/if}
	</div>

	<div class="max-w-7xl mx-auto px-3 sm:px-4 py-4 space-y-4">
		{#if loading}
			<div class="flex justify-center items-center h-64">
				<div class="animate-spin h-10 w-10 border-2 border-[#f5f5f5] border-t-transparent"></div>
			</div>
		{:else}

		<div class="pt-6 pb-2" data-fx-rate={displayRate}>
			{#if !isDataComplete}
				<span class="inline-block text-xs font-semibold fac-minus mb-2">Partial Data</span>
			{/if}
			<p class="text-xs font-semibold tracking-[0.14em] text-[#9a9a9a] mb-1">
				{snapshot ? 'SNAPSHOT Δ' : 'P/L'}
			</p>
			<div class="flex items-center gap-3 sm:gap-4">
				<CurrencyFlag currency={displayCurrency} size={28} />
				<p
					class="fac-display text-6xl sm:text-7xl lg:text-[7rem] font-extrabold tracking-tight leading-none tabular-nums flex items-baseline gap-[0.18em] flex-wrap {!isDataComplete ? 'opacity-60' : ''} {Math.abs(heroValue) < 0.005 ? 'text-[#ececec]' : heroValue >= 0 ? 'fac-plus' : 'fac-minus'}"
				>
					<span class="inline-flex items-baseline whitespace-nowrap">
						<span>{heroAmountParts.whole}</span><span class="pl-hero-frac">{heroAmountParts.frac}</span>
					</span>
					{#if displayCurrency !== 'USD' && showUsdEquiv}
						<span class="text-[0.28em] sm:text-[0.24em] lg:text-[0.22em] font-semibold tracking-normal text-[#ececec]">
							{usdParen(heroValue, heroValue >= 0.005 ? '+' : '', true)}
						</span>
					{/if}
					{#if !snapshot}
						<span
							class="text-[0.22em] sm:text-[0.20em] lg:text-[0.18em] font-semibold tracking-normal {revealBookValues && Math.abs(adjustedProfitLossPercent) >= 0.005 ? (adjustedProfitLossPercent >= 0 ? 'fac-plus' : 'fac-minus') : 'text-[#ececec]'}"
						>
							{bookValue((adjustedProfitLossPercent >= 0.005 ? '+' : '') + formatNumber(adjustedProfitLossPercent, false), revealBookValues)}%
						</span>
					{:else}
						<span class="inline-flex items-baseline gap-2 text-sm font-normal tracking-tight text-[#ececec]">
							<span>
								P/L
								<span class={Math.abs(adjustedProfitLoss) < 0.005 ? 'text-[#ececec]' : adjustedProfitLoss >= 0 ? 'fac-plus' : 'fac-minus'}>
									{bookValue((adjustedProfitLoss >= 0.005 ? '+' : '') + formatNumber(adjustedProfitLoss), true)}
								</span>
							</span>
							<span class={revealBookValues && Math.abs(adjustedProfitLossPercent) >= 0.005 ? (adjustedProfitLossPercent >= 0 ? 'fac-plus' : 'fac-minus') : 'text-[#ececec]'}>
								({bookValue((adjustedProfitLossPercent >= 0.005 ? '+' : '') + formatNumber(adjustedProfitLossPercent, false), revealBookValues)}%)
							</span>
						</span>
					{/if}
				</p>
			</div>
			{#if totalWaitingWD !== 0 || totalDeposits !== 0}
				<p class="text-sm mt-2 tracking-tight text-[#ececec] flex flex-wrap items-center gap-x-4 gap-y-1">
					{#if totalWaitingWD !== 0}
						<span>SUM WD <span class={revealBookValues ? (totalWaitingWD >= 0 ? 'fac-plus-soft' : 'fac-minus-soft') : ''}>{moneyLine(totalWaitingWD, totalWaitingWD >= 0 ? '+' : '', revealBookValues)}</span></span>
					{/if}
					{#if totalDeposits !== 0}
						<span>SUM DP <span class={revealBookValues ? 'fac-minus-soft' : ''}>{moneyLine(totalDeposits, '−', revealBookValues)}</span></span>
					{/if}
				</p>
			{/if}

			<div class="flex items-center gap-3 flex-wrap text-xs mt-2">
				<button on:click={() => takeSnapshot('adjusted')} class="fac-ghost text-xs" disabled={snapshotLoading}>
					{snapshot ? 'RESET SNAPSHOT' : 'TAKE SNAPSHOT'}
				</button>
				{#if snapshot}
					<button on:click={clearSnapshot} class="fac-ghost text-xs" disabled={snapshotLoading}>
						TURN OFF SNAPSHOT
					</button>
				{/if}
			</div>
		</div>

		<div class="flex flex-col gap-1 pb-2 text-xs text-[#ececec]">
			{#if diffLanes.length > 0}
				<div class="flex flex-wrap items-center gap-x-3 gap-y-1.5" aria-label="Unit diffs">
					{#each diffLanes as lane, i (lane.unit)}
						{#if i > 0}
							<span class="inline-block h-4 w-px shrink-0 bg-[#ececec]/35" aria-hidden="true"></span>
						{/if}
						<span class="inline-flex items-center gap-1">
							<span class="tabular-nums {lane.lowEquity ? 'fac-warn' : 'text-[#9a9a9a]'}" title={lane.lowEquity ? 'Low equity' : undefined}>#{lane.unit}</span>
							{#if lane.diffs.length === 0}
								<span class={lane.lowEquity ? 'fac-warn' : 'text-[#5c5c5c]'} title="No open diff">—</span>
							{:else}
								{#each lane.diffs as diff, i (`${lane.unit}-${i}`)}
									<span class="{diff >= 0 ? 'fac-chip-plus' : 'fac-chip-minus'} tabular-nums">
										{diff >= 0 ? '+' : ''}{diff}
									</span>
								{/each}
							{/if}
						</span>
					{/each}
				</div>
			{/if}
		</div>

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
					{#snippet equityResetButton(state: EquityWarningState, unit: number, resetting: number | null)}
						{#if plAlertSettings.equityWarningEnabled && isEquityWarningPaused(state, unit)}
							<button
								type="button"
								on:click={() => resetEquityWarning(unit)}
								class="inline-flex w-full min-h-12 items-center gap-2 px-4 mb-1 fac-display text-lg sm:text-xl font-extrabold tracking-tight bg-[#ffcc33] text-[#0a0a0a] border border-[#ffcc33] transition-opacity duration-150 ease-out hover:bg-[#f5f5f5] hover:border-[#f5f5f5] active:opacity-60 disabled:opacity-45 disabled:cursor-wait disabled:hover:bg-[#ffcc33] disabled:hover:border-[#ffcc33]"
								disabled={resetting !== null}
								aria-busy={resetting === unit}
							>
								{#if resetting === unit}
									<svg class="h-5 w-5 shrink-0 motion-safe:animate-spin" viewBox="0 0 24 24" aria-hidden="true">
										<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" d="M12 3a9 9 0 0 1 9 9" />
									</svg>
									RESETTING...
								{:else}
									RESET EQUITY ALERT
								{/if}
							</button>
						{/if}
					{/snippet}

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
							{@render equityResetButton(equityWarningState, unit, resettingEquityUnit)}
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
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold {legacyDelta >= 0 ? 'fac-plus' : 'fac-minus'}">
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
									{@const unitWD = unitNoteAmount(unitWithdrawals, unit)}
									{@const unitDP = unitNoteAmount(unitDeposits, unit)}
									{@const unitPWD = pendingTotalForAccounts(unitGroups[unit] || [])}
									<div class="flex items-center justify-between mt-1.5">
										<div class="flex items-center gap-x-3 gap-y-0.5 flex-wrap text-xs text-[#ececec]">
											<span>C: {moneyLine(unitInitialCapitals[unit] ?? 0, '', revealBookValues)}</span>
											<span>T: {moneyLine(unitStat.totalBalance, '', revealBookValues)}</span>
											{#if unitWD > 0}
												<span>WD: {moneyLine(unitWD, '+', revealBookValues)}</span>
											{/if}
											{#if unitDP > 0}
												<span>DP: {moneyLine(unitDP, '-', revealBookValues)}</span>
											{/if}
											{#if unitPWD > 0}
												<span class="text-amber-300">PWD: {moneyLine(unitPWD, '', revealBookValues)}</span>
											{/if}
										</div>
										<div class="flex flex-col items-end flex-shrink-0 ml-3 leading-tight">
											<span class="text-xs font-semibold {Math.abs(unitStat.profitLoss) < 0.005 ? 'text-[#ececec]' : unitStat.profitLoss >= 0 ? 'fac-plus' : 'fac-minus'}">
												{moneyLine(unitStat.profitLoss, unitStat.profitLoss >= 0.005 ? '+' : '', true)}
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

								<!-- Row 3: Equity tube per broker. Cash to move sits in one column, clear of unit P/L. -->
								<div class="mt-2 grid grid-cols-[max-content_max-content_minmax(0,1fr)] gap-y-1.5">
									{#each visibleAccounts as account (account.account_number)}
										{@const tube = equityMeter(account.latest_equity, unitInitialCapitals[unit] ?? 0, unitWarningEquityPercentages[unit])}
										{@const sharedBroker = visibleAccounts.filter((a) => a.broker_name === account.broker_name).length > 1}
										{@const brokerLabel = bookBroker(account.broker_name, revealBookValues) + (revealBookValues && sharedBroker ? ' ' + account.account_number.slice(-4) : '')}
										{@const fillClass = tube.zone === 'breach' ? 'is-breach' : tube.zone === 'near' ? 'is-near' : tube.zone === 'unset' ? '' : 'is-ok'}
										<div
											class="col-span-3 grid grid-cols-subgrid items-center gap-x-2"
											title={revealBookValues
												? `${account.broker_name} equity ${formatNumber(account.latest_equity)} · target ${formatNumber(getUnitTargetEquity(unit))} · warning ${formatNumber(getWarningThreshold(unitInitialCapitals[unit] ?? 0, unitWarningEquityPercentages[unit]))}`
												: brokerLabel}
										>
											<span class="min-w-0 truncate text-[10px] leading-none text-[#ececec]">{brokerLabel}</span>
											<span class="text-xs leading-none tabular-nums font-medium whitespace-nowrap">
												{#if tube.zone === 'breach' || tube.zone === 'near'}
													<span class="fac-chip-plus">D {moneyLine(Math.max(0, getUnitTargetEquity(unit) - account.latest_equity), '', revealBookValues)}</span>
												{:else if tube.zone === 'over'}
													<span class="fac-chip-minus">W {moneyLine(tube.mark, '', revealBookValues)}</span>
												{:else if tube.zone === 'ok' && tube.mark > 0.005}
													<span class="fac-chip-plus">D {moneyLine(tube.mark, '', revealBookValues)}</span>
												{:else if tube.zone === 'unset'}
													<span class="text-[#ececec]">set capital</span>
												{:else}
													<span class="text-[#ececec]">at target</span>
												{/if}
											</span>
											<div
												class="fac-tube min-w-0"
												role="img"
												aria-label={tube.zone === 'breach'
													? `${brokerLabel} equity below warning`
													: tube.zone === 'near'
														? `${brokerLabel} equity near warning`
														: tube.zone === 'over'
															? `${brokerLabel} equity past target`
															: tube.zone === 'unset'
																? `${brokerLabel} equity, no target`
																: `${brokerLabel} equity`}
											>
												<div class="fac-tube-main">
													<div class="fac-tube-clip">
														<div class="fac-tube-fill {fillClass}" style="transform: scaleX({tube.fillPct / 100})"></div>
													</div>
													{#if tube.zone !== 'unset'}
														<div class="fac-tube-warn" class:is-alert={tube.zone === 'near' || tube.zone === 'breach'} style="left: {tube.warnPct}%" title="Warning"></div>
													{/if}
												</div>
												<div class="fac-tube-over" title="Past target">
													<div class="fac-tube-clip">
														<div class="fac-tube-over-fill" style="transform: scaleX({tube.overPct / 100})"></div>
													</div>
												</div>
											</div>
										</div>
									{/each}
								</div>
							</div>
							
							{#if unitVisibility[unit] !== false}
							<div class="px-4 py-3 border-t border-stone-700/50 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
								<div class="grid grid-cols-2 gap-3 sm:flex sm:items-end">
									<div class="block text-[11px] text-[#ececec]">
										WD Note (+)
										<div class="mt-1 flex items-center gap-1.5">
											{#if revealBookValues}
												<input
													type="number"
													min="0"
													step="0.01"
													value={unitNoteAmount(unitWithdrawals, unit)}
													on:change={(e) => handleUnitWithdrawalChange(unit, e)}
													class="w-full sm:w-36 min-w-0 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm tabular-nums focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
													aria-label={`WD Note for unit ${unit}`}
												/>
												<button
													type="button"
													on:click={() => openNoteAdd(unit, 'wd')}
													class="fac-ghost shrink-0 px-3 text-xs"
													title="Add this round to WD Note"
													aria-label={`Add this round to WD Note for unit ${unit}`}
												>
													Add
												</button>
											{:else}
												<div class="w-full sm:w-36 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm leading-[2.75rem]">{MASK}</div>
											{/if}
										</div>
									</div>
									<div class="block text-[11px] text-[#ececec]">
										DP Note (-)
										<div class="mt-1 flex items-center gap-1.5">
											{#if revealBookValues}
												<input
													type="number"
													min="0"
													step="0.01"
													value={unitNoteAmount(unitDeposits, unit)}
													on:change={(e) => handleUnitDepositChange(unit, e)}
													class="w-full sm:w-36 min-w-0 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm tabular-nums focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
													aria-label={`DP Note for unit ${unit}`}
												/>
												<button
													type="button"
													on:click={() => openNoteAdd(unit, 'dp')}
													class="fac-ghost shrink-0 px-3 text-xs"
													title="Add this round to DP Note"
													aria-label={`Add this round to DP Note for unit ${unit}`}
												>
													Add
												</button>
											{:else}
												<div class="w-full sm:w-36 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm leading-[2.75rem]">{MASK}</div>
											{/if}
										</div>
									</div>
								</div>
								<div class="flex items-center gap-2 flex-wrap">
									{#if isUnitNotNetted(unit)}
										<button type="button" on:click={() => consolidateGroupWDDP(unit)} disabled={consolidatingUnits.has(unit)} class="text-[11px] min-h-11 px-2.5 rounded-md font-medium bg-cyan-900/40 hover:bg-cyan-900/60 text-cyan-400 disabled:opacity-50 transition-colors">
											{consolidatingUnits.has(unit) ? '...' : 'Simplify WD/DP'}
										</button>
									{/if}
									{#if unitStat && Math.abs(unitStat.profitLoss) >= 0.01}
										<button type="button" on:click={() => adjustUnitPLToZero(unit)} disabled={adjustingPLUnits.has(unit)} class="text-[11px] min-h-11 px-2.5 rounded-md font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
											{adjustingPLUnits.has(unit) ? '...' : 'Set P/L Zero'}
										</button>
									{/if}
								</div>
							</div>

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
											<div class="flex items-start gap-2 min-w-0">
												<button
													type="button"
													on:click|stopPropagation={() => openPendingDialog(account)}
													class="relative mt-0.5 inline-flex items-center justify-center w-8 h-8 rounded-md border {pendingTotalForAccount(account.account_number) > 0 ? 'border-amber-700/70 text-amber-300' : 'border-stone-600 text-[#ececec]'} hover:bg-stone-700 hover:text-[#f5f5f5]"
													title="Pending withdrawal"
													aria-label={`Pending withdrawal for ${account.account_number}`}
												>
													<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
														<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l2.5 1.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
													</svg>
													{#if pendingTotalForAccount(account.account_number) > 0}
														<span class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-400"></span>
													{/if}
												</button>
												<div class="min-w-0">
													<div class="font-mono font-semibold text-[#f5f5f5] text-sm">{account.account_number}</div>
													<div class="text-xs text-[#ececec] truncate">{account.account_name} · {account.broker_name}</div>
													{#if pendingTotalForAccount(account.account_number) > 0}
														<div class="text-[10px] text-amber-300 tabular-nums">PWD {moneyLine(pendingTotalForAccount(account.account_number), '', revealBookValues)}</div>
													{/if}
												</div>
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
										<div class="grid grid-cols-3 gap-2 text-xs">
											<div>
												<div class="text-[#ececec]">Balance</div>
												<div class="font-medium text-[#f5f5f5] tabular-nums">{moneyLine(account.latest_balance, '', revealBookValues)}</div>
											</div>
											<div>
												<div class="text-[#ececec]">Equity</div>
												<div class="font-medium text-[#f5f5f5] tabular-nums">{moneyLine(account.latest_equity, '', revealBookValues)}</div>
											</div>
											<div>
												<div class="text-[#ececec]">Adjust</div>
												<div class="font-medium tabular-nums {adjust > 0 ? 'fac-plus' : adjust < 0 ? 'fac-minus' : 'text-[#ececec]'}">
													{#if adjust > 0}
														D {moneyLine(Math.abs(adjust), '', revealBookValues)}
													{:else if adjust < 0}
														W {moneyLine(Math.abs(adjust), '', revealBookValues)}
													{:else}
														{moneyLine(0, '', revealBookValues)}
													{/if}
												</div>
											</div>
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
                                                    D {moneyLine(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity), '', revealBookValues)}
                                                {:else if getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                    W {moneyLine(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity), '', revealBookValues)}
													{:else}
														{moneyLine(0, '', revealBookValues)}
													{/if}
												</td>
												<td class="py-1.5 px-2">
													<div class="flex items-start gap-1.5">
														<button
															type="button"
															on:click|stopPropagation={() => openPendingDialog(account)}
															class="relative mt-0.5 inline-flex items-center justify-center w-7 h-7 rounded-md border {pendingTotalForAccount(account.account_number) > 0 ? 'border-amber-700/70 text-amber-300' : 'border-stone-600 text-[#ececec]'} hover:bg-stone-700 hover:text-[#f5f5f5]"
															title="Pending withdrawal"
															aria-label={`Pending withdrawal for ${account.account_number}`}
														>
															<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
																<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l2.5 1.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
															</svg>
															{#if pendingTotalForAccount(account.account_number) > 0}
																<span class="absolute -top-0.5 -right-0.5 w-2 h-2 rounded-full bg-amber-400"></span>
															{/if}
														</button>
														<div class="flex flex-col leading-tight min-w-0">
															<span class="font-mono font-semibold text-[#f5f5f5] text-xs">
																{account.account_number}
															</span>
															<span class="text-[#ececec] text-xs truncate" title={account.account_name}
																>{shortName(account.account_name)}</span
															>
															{#if pendingTotalForAccount(account.account_number) > 0}
																<span class="text-[10px] text-amber-300 tabular-nums">PWD {moneyLine(pendingTotalForAccount(account.account_number), '', revealBookValues)}</span>
															{/if}
														</div>
													</div>
												</td>
												<td class="py-1.5 px-2 text-[#ececec] text-xs">{account.broker_name}</td>
												<td class="py-1.5 px-2 text-right font-medium text-[#f5f5f5] text-xs"
													>{moneyLine(account.latest_balance, '', revealBookValues)}</td
												>
												<td class="py-1.5 px-2 text-right font-medium text-[#f5f5f5] text-xs"
													>{moneyLine(account.latest_equity, '', revealBookValues)}</td
												>
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
							<span class="text-[10px] text-[#ececec] mt-0.5">Capital: {moneyLine(initialCapital, '', revealBookValues)}</span>
						{/if}
					</div>
					<div class="flex items-center gap-2 flex-wrap">
						<span class="text-lg font-bold text-[#f5f5f5]">
							{moneyLine(unitStats.reduce((sum, s) => sum + s.totalBalance, 0), '', revealBookValues)}
						</span>
						{#if unitStats.some((s) => Math.abs(s.profitLoss) >= 0.01)}
							<button on:click={adjustAllGroupsPL} disabled={adjustingAllPL} class="text-[11px] min-h-9 px-2.5 rounded-md font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
								{adjustingAllPL ? '...' : 'Set P/L Zero All'}
							</button>
						{/if}
						{#if Object.keys(unitGroups).some((unitStr) => isUnitNotNetted(parseInt(unitStr)))}
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
									<span class="font-semibold text-[#f5f5f5]">{moneyLine(brokerData.equity, '', revealBookValues)}</span>
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
														<span class="font-medium text-[#f5f5f5] whitespace-nowrap">{moneyLine(nameData.equity, '', revealBookValues)}</span>
													</button>
													{#if expandedBrokerNames.has(nameKey)}
														<div class="ml-5 mt-0.5 space-y-0.5">
															{#each nameData.accounts.sort((a, b) => b.equity - a.equity) as acct}
																<div class="flex items-center justify-between text-[10px] px-2.5 py-0.5 rounded bg-stone-800/40">
																	<span class="text-[#ececec] tabular-nums">{acct.number}</span>
																	<span class="font-medium text-[#ececec] whitespace-nowrap">{moneyLine(acct.equity, '', revealBookValues)}</span>
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
														<span class="font-medium text-[#f5f5f5] whitespace-nowrap">{moneyLine(nameData.equity, '', revealBookValues)}</span>
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

		{#if summaries.length > 0 || pendingSummaryRows.length > 0}
			{@const pendingTotal = pendingSummaryRows.reduce((sum, item) => sum + item.amount, 0)}
			<div class="py-4 border-t border-stone-700/60">
				<div class="flex items-center justify-between gap-2 mb-2">
					<h3 class="text-sm font-semibold text-[#f5f5f5]">Pending Withdrawals</h3>
					{#if pendingTotal > 0}
						<span class="text-xs text-amber-300 tabular-nums">Total {moneyLine(pendingTotal, '', revealBookValues)}</span>
					{/if}
				</div>
				<div class="md:hidden divide-y divide-[#3a3a3a] fac-sheet">
					{#each pendingSummaryRows as entry (entry.id)}
						<div class="px-4 py-3 space-y-1.5">
							<div class="flex items-start justify-between gap-2">
								<div class="min-w-0">
									<div class="font-mono font-semibold text-[#f5f5f5] text-sm">{entry.account_number}</div>
									<div class="text-xs text-[#ececec] truncate">{entry.account_name} · {entry.broker_name}</div>
								</div>
								<button
									type="button"
									on:click={() => requestPendingDelete(entry)}
									class="min-h-9 px-2 text-xs fac-minus"
									aria-label={`Delete pending withdrawal ${entry.account_number}`}
								>
									Delete
								</button>
							</div>
							<div class="flex items-center justify-between text-xs text-[#ececec]">
								<span>Unit {entry.unit === 0 ? 'Unknown' : entry.unit}</span>
								<span class="text-amber-300 tabular-nums">{moneyLine(entry.amount, '', revealBookValues)}</span>
							</div>
							<div class="text-[11px] text-[#ececec]">{formatLocalDateTime(entry.withdrawn_at)}</div>
							{#if entry.note}
								<div class="text-[11px] text-[#ececec]">{entry.note}</div>
							{/if}
						</div>
					{/each}
					{#if pendingSummaryRows.length === 0}
						<div class="px-4 py-6 text-xs text-[#ececec]">No pending withdrawals.</div>
					{/if}
				</div>
				<div class="hidden md:block overflow-x-auto fac-sheet">
					<table class="w-full text-xs">
						<thead>
							<tr class="border-b border-stone-700">
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Date</th>
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Unit</th>
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Account</th>
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Name</th>
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Broker</th>
								<th class="text-right py-1.5 px-2 text-[#ececec] font-medium">Amount</th>
								<th class="text-left py-1.5 px-2 text-[#ececec] font-medium">Note</th>
								<th class="text-right py-1.5 px-2 text-[#ececec] font-medium"></th>
							</tr>
						</thead>
						<tbody>
							{#each pendingSummaryRows as entry (entry.id)}
								<tr class="border-b border-stone-700/50">
									<td class="py-1.5 px-2 text-[#ececec] tabular-nums">{formatLocalDateTime(entry.withdrawn_at)}</td>
									<td class="py-1.5 px-2 text-[#ececec]">{entry.unit === 0 ? 'Unknown' : entry.unit}</td>
									<td class="py-1.5 px-2 font-mono text-[#f5f5f5]">{entry.account_number}</td>
									<td class="py-1.5 px-2 text-[#ececec] truncate" title={entry.account_name}>{shortName(entry.account_name)}</td>
									<td class="py-1.5 px-2 text-[#ececec]">{entry.broker_name}</td>
									<td class="py-1.5 px-2 text-right text-amber-300 tabular-nums">{moneyLine(entry.amount, '', revealBookValues)}</td>
									<td class="py-1.5 px-2 text-[#ececec] truncate" title={entry.note}>{entry.note || '—'}</td>
									<td class="py-1.5 px-2 text-right">
										<button
											type="button"
											on:click={() => requestPendingDelete(entry)}
											class="min-h-9 px-2 text-xs fac-minus"
											aria-label={`Delete pending withdrawal ${entry.account_number}`}
										>
											Delete
										</button>
									</td>
								</tr>
							{/each}
							{#if pendingSummaryRows.length === 0}
								<tr>
									<td colspan="8" class="py-6 px-2 text-center text-[#ececec]">No pending withdrawals.</td>
								</tr>
							{/if}
						</tbody>
					</table>
				</div>
			</div>
			<div class="py-5 border-t border-stone-700/60">
				<div class="flex items-start justify-between gap-3">
					<div class="min-w-0">
						{#if walletNameEditing}
							<form class="flex items-center gap-2" on:submit|preventDefault={commitWalletName}>
								<input
									type="text"
									maxlength={EXTERNAL_WALLET_NAME_MAX}
									bind:value={walletNameDraft}
									class="w-40 min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
									aria-label="Wallet name"
								/>
								<button type="submit" class="min-h-11 px-3 text-sm text-[#f5f5f5]">Save</button>
								<button type="button" on:click={cancelWalletNameEdit} class="min-h-11 px-2 text-sm text-[#ececec]">Cancel</button>
							</form>
						{:else}
							<div class="flex items-center gap-2 min-w-0">
								<h3 class="text-base font-semibold text-[#f5f5f5] truncate">{externalWallet.name}</h3>
								<button
									type="button"
									on:click={startWalletNameEdit}
									class="shrink-0 min-h-9 px-2 text-xs text-[#ececec] hover:text-[#f5f5f5]"
								>
									Edit
								</button>
							</div>
						{/if}
					</div>
					<button
						type="button"
						on:click={openWalletAdjust}
						disabled={!revealBookValues}
						class="shrink-0 min-h-11 px-3 rounded-md text-sm font-medium bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 disabled:opacity-40"
					>
						Adjust to latest
					</button>
				</div>
				<div class="mt-3 fac-display text-4xl sm:text-5xl font-extrabold tracking-tight tabular-nums text-[#f5f5f5] leading-none">
					{moneyLine(externalWallet.balance, '', revealBookValues)}
				</div>
				{#if externalWallet.updated_at}
					<div class="mt-2 text-xs text-[#ececec] tabular-nums">Updated {formatLocalDateTime(externalWallet.updated_at)}</div>
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
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2">P/L Alerts</legend>
						<p class="text-xs text-[#ececec] mb-3">
							Email when adjusted P/L crosses a threshold, or when a unit hits its warning equity %. Each alert sends once, then stays paused until you reset it.
						</p>
						<div class="space-y-3">
							<label class="inline-flex items-center gap-2 text-sm text-[#ececec]">
								<input
									type="checkbox"
									checked={draftPlAlert.equityWarningEnabled}
									on:change={(e) => {
										draftPlAlert = { ...draftPlAlert, equityWarningEnabled: (e.target as HTMLInputElement).checked };
									}}
									class="border-stone-600 bg-stone-700 text-[#f5f5f5] focus:ring-[#f5f5f5]"
								/>
								<span>Low equity alert</span>
							</label>
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


				<!-- WD / DP Notes (per unit group) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-[#f5f5f5] mb-2">WD / DP Notes</legend>
						<p class="text-xs text-[#ececec] mb-2">
							One WD Note and one DP Note per unit group. Clearing a row, including a Wallet update from DP, applies when you press Save.
						</p>
						<div class="space-y-2 max-h-64 overflow-y-auto pr-1">
							{#each settingsNoteUnits as unit}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl px-3 py-2 space-y-2">
									<div class="text-sm text-[#f5f5f5]">Unit {unit === 0 ? 'Unknown' : unit} ({getDraftUnitDisplayName(unit)})</div>
									{#if unitNoteAmount(draftWithdrawals, unit) > 0}
										<div class="flex items-center justify-between gap-2">
											<span class="text-xs text-[#ececec]">WD Note (+)</span>
											<div class="flex items-center gap-2">
												<span class="text-xs text-[#ececec] tabular-nums">{formatNumber(unitNoteAmount(draftWithdrawals, unit), false)}</span>
												<button
													type="button"
													on:click={() => { draftWithdrawals = { ...draftWithdrawals, [unit]: 0 }; }}
													class="fac-minus hover:fac-minus transition-colors"
													aria-label={`Remove WD note for unit ${unit}`}
												>
													<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
														<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
													</svg>
												</button>
											</div>
										</div>
									{/if}
									{#if unitNoteAmount(draftDeposits, unit) > 0}
										<div class="flex items-center justify-between gap-2">
											<span class="text-xs text-[#ececec]">DP Note (-)</span>
											<div class="flex items-center gap-2">
												<span class="text-xs text-[#ececec] tabular-nums">{formatNumber(unitNoteAmount(draftDeposits, unit), false)}</span>
												<button
													type="button"
													on:click={() => requestSettingsDpClear(unit)}
													class="fac-minus hover:fac-minus transition-colors"
													aria-label={`Remove DP note for unit ${unit}`}
												>
													<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
														<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
													</svg>
												</button>
											</div>
										</div>
									{/if}
								</div>
							{/each}
							{#if settingsNoteUnits.length === 0}
								<div class="text-xs text-[#ececec]">No non-zero WD or DP notes.</div>
							{/if}
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

{#if pendingDialogAccount}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 overflow-y-auto flex items-stretch md:items-center justify-center p-0 md:p-6"
		on:click={closePendingDialog}
		on:keydown={(e) => e.key === 'Escape' && closePendingDialog()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="pending-wd-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] text-[#f5f5f5] w-full max-w-lg md:mx-4 md:my-8 flex flex-col h-full md:h-auto max-h-none md:max-h-[85vh] border-0 md:border md:border-[#f5f5f5]"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="flex justify-between items-center px-4 pt-[max(1rem,env(safe-area-inset-top))] pb-3 sm:p-6 sm:pb-4">
				<div class="min-w-0">
					<h2 id="pending-wd-title" class="text-base font-semibold text-[#f5f5f5]">Pending Withdrawal</h2>
					<p class="text-xs text-[#ececec] truncate">
						{pendingDialogAccount.account_number} · {pendingDialogAccount.account_name}
					</p>
				</div>
				<button
					type="button"
					on:click={closePendingDialog}
					class="fac-ghost min-h-11 px-3"
					disabled={pendingSaving}
				>
					Close
				</button>
			</div>
			<form
				class="px-4 sm:px-6 pb-4 space-y-3"
				on:submit|preventDefault={submitPendingWithdrawal}
			>
				<label class="block text-[11px] text-[#ececec]">
					Amount
					<input
						type="number"
						min="0.01"
						step="0.01"
						bind:value={pendingAmount}
						class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
						required
					/>
				</label>
				<label class="block text-[11px] text-[#ececec]">
					Note (optional)
					<input
						type="text"
						maxlength={PENDING_NOTE_MAX_LENGTH}
						bind:value={pendingNote}
						class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
					/>
				</label>
				<label class="block text-[11px] text-[#ececec]">
					Withdrawn at (optional)
					<input
						type="datetime-local"
						bind:value={pendingDate}
						class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-sm focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
					/>
				</label>
				{#if pendingFormError}
					<p class="text-xs fac-minus">{pendingFormError}</p>
				{/if}
				<button
					type="submit"
					disabled={pendingSaving}
					class="fac-ghost w-full min-h-11"
				>
					{pendingSaving ? 'Saving...' : 'Add pending'}
				</button>
			</form>
			<div class="px-4 sm:px-6 pb-[max(1rem,env(safe-area-inset-bottom))] overflow-y-auto">
				<h3 class="text-xs font-semibold text-[#ececec] uppercase tracking-wider mb-2">History</h3>
				<div class="divide-y divide-stone-700/60 border border-stone-700/60">
					{#each pendingDialogHistory as entry (entry.id)}
						<div class="flex items-start justify-between gap-2 px-3 py-2.5">
							<div class="min-w-0">
								<div class="text-sm text-amber-300 tabular-nums">{moneyLine(entry.amount, '', revealBookValues)}</div>
								<div class="text-[11px] text-[#ececec]">{formatLocalDateTime(entry.withdrawn_at)}</div>
								{#if entry.note}
									<div class="text-[11px] text-[#ececec] truncate">{entry.note}</div>
								{/if}
							</div>
							<button
								type="button"
								on:click={() => requestPendingDelete(entry)}
								class="min-h-9 px-2 text-xs fac-minus"
								aria-label="Delete pending withdrawal"
							>
								Delete
							</button>
						</div>
					{/each}
					{#if pendingDialogHistory.length === 0}
						<div class="px-3 py-4 text-xs text-[#ececec]">No pending withdrawals for this account.</div>
					{/if}
				</div>
			</div>
		</div>
	</div>
{/if}

{#if pendingDeleteTarget}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-[70] flex items-center justify-center p-4 sm:p-6"
		on:click={closePendingDelete}
		on:keydown={(e) => e.key === 'Escape' && closePendingDelete()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="pending-delete-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] border border-[#ff4d4d] w-full max-w-md mx-4 p-2"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6 relative">
				<button
					type="button"
					on:click={closePendingDelete}
					disabled={pendingDeleting}
					class="absolute top-4 right-4 min-h-11 min-w-11 inline-flex items-center justify-center text-[#ececec] hover:text-[#f5f5f5]"
					aria-label="Close"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
				<h3 id="pending-delete-title" class="text-lg font-semibold text-[#f5f5f5] mb-2 pr-10">Delete pending withdrawal?</h3>
				<p class="text-sm text-[#ececec] mb-2">
					{pendingDeleteTarget.account_number}
					· {moneyLine(pendingDeleteTarget.amount, '', true)}
					{#if pendingDeleteTarget.note}
						· {pendingDeleteTarget.note}
					{/if}
				</p>
				<p class="text-sm text-[#ececec] mb-4 tabular-nums">
					Add to Wallet: {moneyLine(externalWallet.balance, '', true)} → {moneyLine(roundMoney(externalWallet.balance + pendingDeleteTarget.amount), '', true)}
				</p>
				<div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-end gap-3">
					<button
						type="button"
						on:click={() => confirmPendingDelete(false)}
						disabled={pendingDeleting}
						class="min-h-11 px-4 py-2 rounded-xl bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 disabled:opacity-50 transition-colors"
					>
						Delete only
					</button>
					<button
						type="button"
						on:click={() => confirmPendingDelete(true)}
						disabled={pendingDeleting}
						class="min-h-11 px-4 py-2 rounded-xl bg-red-500 text-white hover:bg-red-600 disabled:bg-stone-700 disabled:text-[#ececec] disabled:cursor-not-allowed transition-colors"
					>
						{pendingDeleting ? 'Deleting...' : 'Delete and add to Wallet'}
					</button>
				</div>
			</div>
		</div>
	</div>
{/if}

{#if noteAdd}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-[60] flex items-center justify-center p-4 sm:p-6"
		on:click={closeNoteAdd}
		on:keydown={(e) => e.key === 'Escape' && closeNoteAdd()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="note-add-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] border border-[#f5f5f5] w-full max-w-md mx-4 p-2"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6 relative">
				<button
					type="button"
					on:click={closeNoteAdd}
					disabled={noteAddSaving}
					class="absolute top-4 right-4 min-h-11 min-w-11 inline-flex items-center justify-center text-[#ececec] hover:text-[#f5f5f5]"
					aria-label="Close"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
				<h3 id="note-add-title" class="text-lg font-semibold text-[#f5f5f5] mb-2 pr-10">
					Add to {noteAdd.side === 'wd' ? 'WD Note' : 'DP Note'}
				</h3>
				<p class="text-sm text-[#ececec] mb-4">
					Unit {noteAdd.unit === 0 ? 'Unknown' : noteAdd.unit}
					· now {formatNumber(noteAddCurrent, false)}
				</p>
				<form on:submit|preventDefault={submitNoteAdd}>
					<label class="block text-[11px] text-[#ececec]">
						This round
						<input
							type="number"
							min="0.01"
							step="0.01"
							bind:this={noteAddInput}
							bind:value={noteAddAmount}
							class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm tabular-nums focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
							aria-label="Amount to add this round"
						/>
					</label>
					<p class="text-sm text-[#f5f5f5] mt-3 tabular-nums">
						{formatNumber(noteAddCurrent, false)} + {formatNumber(noteAddDelta, false)} = {formatNumber(noteAddNext, false)}
					</p>
					{#if noteAddError}
						<p class="text-xs fac-minus mt-2">{noteAddError}</p>
					{/if}
					<div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-end gap-3 mt-4">
						<button
							type="button"
							on:click={closeNoteAdd}
							disabled={noteAddSaving}
							class="min-h-11 px-4 py-2 rounded-xl bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 disabled:opacity-50 transition-colors"
						>
							Cancel
						</button>
						<button
							type="submit"
							disabled={noteAddSaving || noteAddDelta <= 0}
							class="min-h-11 px-4 py-2 rounded-xl bg-[#f5f5f5] text-[#0a0a0a] hover:bg-white disabled:opacity-50 transition-colors"
						>
							{noteAddSaving ? 'Saving...' : 'Add'}
						</button>
					</div>
				</form>
			</div>
		</div>
	</div>
{/if}

{#if walletPrompt}
	{@const effect = walletEffect(walletPrompt.previous, walletPrompt.next)}
	{@const before = walletPrompt.kind === 'settings-dp' ? roundMoney(externalWallet.balance + settingsWalletCredit) : externalWallet.balance}
	{@const after = roundMoney(before + effect)}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-[80] flex items-center justify-center p-4 sm:p-6"
		on:click={dismissWalletPrompt}
		on:keydown={(e) => e.key === 'Escape' && dismissWalletPrompt()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="wallet-prompt-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] border border-[#f5f5f5] w-full max-w-md mx-4 p-2"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6 relative">
				<button
					type="button"
					on:click={dismissWalletPrompt}
					disabled={walletPromptSaving}
					class="absolute top-4 right-4 min-h-11 min-w-11 inline-flex items-center justify-center text-[#ececec] hover:text-[#f5f5f5]"
					aria-label="Close"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
				<h3 id="wallet-prompt-title" class="text-lg font-semibold text-[#f5f5f5] mb-2 pr-10">Update Wallet?</h3>
				<p class="text-sm text-[#ececec] mb-3">
					Unit {walletPrompt.unit === 0 ? 'Unknown' : walletPrompt.unit} DP Note
					{formatNumber(walletPrompt.previous, false)} → {formatNumber(walletPrompt.next, false)}
				</p>
				<p class="text-sm text-[#f5f5f5] mb-1 tabular-nums">
					Difference {formatNumber(Math.abs(effect), false)}
					{effect >= 0 ? 'added to Wallet' : 'deducted from Wallet'}
				</p>
				<p class="text-sm text-[#ececec] mb-4 tabular-nums">
					Wallet {formatNumber(before, false)} → {formatNumber(after, false)}
				</p>
				<div class="flex flex-col sm:flex-row items-stretch sm:items-center justify-end gap-3">
					{#if walletPrompt.kind === 'settings-dp'}
						<button
							type="button"
							on:click={() => confirmWalletPrompt(false)}
							class="min-h-11 px-4 py-2 rounded-xl bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 transition-colors"
						>
							Clear DP only
						</button>
						<button
							type="button"
							on:click={() => confirmWalletPrompt(true)}
							class="min-h-11 px-4 py-2 rounded-xl bg-[#f5f5f5] text-[#0a0a0a] hover:bg-white transition-colors"
						>
							Clear DP and update Wallet
						</button>
					{:else}
						<button
							type="button"
							on:click={() => confirmWalletPrompt(false)}
							disabled={walletPromptSaving}
							class="min-h-11 px-4 py-2 rounded-xl bg-stone-700 text-[#f5f5f5] hover:bg-stone-600 disabled:opacity-50 transition-colors"
						>
							Don't update Wallet
						</button>
						<button
							type="button"
							on:click={() => confirmWalletPrompt(true)}
							disabled={walletPromptSaving}
							class="min-h-11 px-4 py-2 rounded-xl bg-[#f5f5f5] text-[#0a0a0a] hover:bg-white disabled:opacity-50 transition-colors"
						>
							{walletPromptSaving ? 'Saving...' : 'Update Wallet'}
						</button>
					{/if}
				</div>
			</div>
		</div>
	</div>
{/if}

{#if walletAdjustOpen}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-[80] flex items-center justify-center p-4 sm:p-6"
		on:click={closeWalletAdjust}
		on:keydown={(e) => e.key === 'Escape' && closeWalletAdjust()}
		role="dialog"
		aria-modal="true"
		aria-labelledby="wallet-adjust-title"
		tabindex="-1"
	>
		<div
			class="bg-[#0a0a0a] border border-[#f5f5f5] w-full max-w-md mx-4 p-2"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<form class="p-6 relative" on:submit|preventDefault={applyWalletAdjust}>
				<button
					type="button"
					on:click={closeWalletAdjust}
					disabled={walletAdjustSaving}
					class="absolute top-4 right-4 min-h-11 min-w-11 inline-flex items-center justify-center text-[#ececec] hover:text-[#f5f5f5]"
					aria-label="Close"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
				<h3 id="wallet-adjust-title" class="text-lg font-semibold text-[#f5f5f5] mb-2 pr-10">Adjust Wallet</h3>
				<p class="text-sm text-[#ececec] mb-3 tabular-nums">Recorded {formatNumber(externalWallet.balance, false)}</p>
				<label class="block text-[11px] text-[#ececec] mb-4">
					Latest actual balance
					<input
						type="number"
						step="0.01"
						bind:value={walletAdjustValue}
						class="mt-1 w-full min-h-11 border border-stone-600 bg-stone-700 text-[#f5f5f5] rounded-md px-2 text-right text-sm tabular-nums focus:ring-1 focus:ring-[#f5f5f5] focus:border-[#f5f5f5]"
						required
					/>
				</label>
				<button
					type="submit"
					disabled={walletAdjustSaving}
					class="min-h-11 w-full px-4 py-2 rounded-xl bg-[#f5f5f5] text-[#0a0a0a] hover:bg-white disabled:opacity-50 transition-colors"
				>
					{walletAdjustSaving ? 'Saving...' : 'Replace with latest'}
				</button>
			</form>
		</div>
	</div>
{/if}

<style>
	.pl-hero-frac {
		font-size: 0.38em;
		font-weight: 600;
		letter-spacing: 0;
		opacity: 0.62;
	}
</style>
