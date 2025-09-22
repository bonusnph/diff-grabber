<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { AccountSummary, DashboardStats } from '$lib/types.js';

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
	// Filters (Broker / Account Name)
	let activeBrokers: Set<string> = new Set();
	let activeAccountNames: Set<string> = new Set();
	let filtersInitialized = false;
	let showFilters = false;

	// Unit visibility state (default all expanded)
	let unitVisibility: Record<number, boolean> = {};

	// Pause auto fetch when settings modal is open
	$: (() => {
		if (showSettingsModal) {
			autoFetchEnabled = false;
		} else if (isAuthenticated) {
			autoFetchEnabled = true;
		}
	})();

	// App is ready only after auth and settings loaded
	$: appReady = isAuthenticated && settingsLoaded;

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


	// PIN Protection
	let isAuthenticated = false;
	let showPinModal = true;
	let pinInput = '';
	let pinError = '';
	let correctPin = '250514';
	let pinLoading = false;

	const AUTH_COOKIE_NAME = 'pm_auth_v1';
	const AUTH_MAX_AGE_SEC = 24 * 60 * 60;

	function setCookie(name: string, value: string, maxAgeSeconds: number) {
		document.cookie = `${name}=${encodeURIComponent(value)}; path=/; max-age=${maxAgeSeconds}; samesite=lax`;
	}

	function getCookie(name: string): string | null {
		const pattern = `; ${name}=`;
		const parts = `; ${document.cookie}`.split(pattern);
		if (parts.length < 2) return null;
		const value = parts.pop()!.split(';').shift();
		return value ? decodeURIComponent(value) : null;
	}

	function deleteCookie(name: string) {
		document.cookie = `${name}=; path=/; max-age=0; samesite=lax`;
	}

	function persistAuth() {
		try {
			setCookie(AUTH_COOKIE_NAME, '1', AUTH_MAX_AGE_SEC);
		} catch (_) {}
	}

	function clearPersistedAuth() {
		try {
			deleteCookie(AUTH_COOKIE_NAME);
		} catch (_) {}
	}

	async function checkPersistedAuth(): Promise<boolean> {
		try {
			const has = getCookie(AUTH_COOKIE_NAME);
			if (!has) return false;
			isAuthenticated = true;
			showPinModal = false;
			pinInput = '';
			pinError = '';
			// Start loading data after authentication
			await loadInitialCapital();
			await fetchData();
			startPolling();
			return true;
		} catch (_) {
			return false;
		}
	}

	function logout() {
		clearPersistedAuth();
		isAuthenticated = false;
		showPinModal = true;
		pinInput = '';
		pinError = '';
		stopPolling();
	}

	// Unit mappings editing
	let newUnitNumber = '';
	let newUnitName = '';
	// Unit-specific broker margin form
	let newUnitBrokerUnit = '';
	let newUnitBrokerName = '';
	let newUnitBrokerMargin = '';

	// Dynamic Unit Settings editing (Initial Capital & Warn %)
	let newUnitSettingNumber: string = '';
	let newUnitSettingCap: string = '';
	let newUnitSettingWarn: string = '';

    function addUnitSetting() {
		const unit = parseInt(newUnitSettingNumber);
		if (isNaN(unit) || unit < 1) return;
		const capParsed = parseFloat(newUnitSettingCap);
		const warnParsed = parseFloat(newUnitSettingWarn);
		const cap = isNaN(capParsed) || capParsed < 0 ? 0 : capParsed;
		const warn = isNaN(warnParsed) || warnParsed < 1 || warnParsed > 100 ? 30 : warnParsed;
		unitInitialCapitals = { ...unitInitialCapitals, [unit]: cap };
		unitWarningEquityPercentages = { ...unitWarningEquityPercentages, [unit]: warn };
        // ensure unitMappings has a placeholder to make unit visible if user has no mapping yet
        if (!(unit in unitMappings)) {
            unitMappings = { ...unitMappings, [unit]: '' };
        }
		newUnitSettingNumber = '';
		newUnitSettingCap = '';
		newUnitSettingWarn = '';
	}

	// Computed list of units for Unit Settings (union of keys)
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

	// Check if account is trading (balance != equity)
	function isTrading(account: AccountSummary): boolean {
		const balanceDiff = Math.abs(account.latest_balance - account.latest_equity);
		return balanceDiff > 0.01; // Consider difference > 0.01 as trading
	}

	// Count trading accounts and calculate trading pairs
	$: tradingAccountsCount = summaries.filter(isTrading).length;
	$: tradingPairs = Math.ceil(tradingAccountsCount / 2);

    $: profitLossPercent = initialCapital > 0 ? (stats.profit_loss / initialCapital) * 100 : 0;
	$: totalWaitingWD = Object.values(accountWithdrawals || {}).reduce(
		(sum, v) => sum + (typeof v === 'number' ? v : 0),
		0
	);
	$: adjustedProfitLoss = (stats?.profit_loss || 0) + (totalWaitingWD || 0);
	$: adjustedProfitLossPercent =
		initialCapital > 0 ? (adjustedProfitLoss / initialCapital) * 100 : 0;

	// Snapshot data returned from server
	let snapshot: { value: number; kind: 'adjusted' | 'real'; timestamp: string } | null = null;
	let snapshotDelta: number | null = null;

	let unitDeltaSummaries: Array<{ unit: number; delta: number | null; tradingCount: number }> = [];
	let positivePairs: Array<{ unit: number; delta: number | null; tradingCount: number }> = [];
	let negativePairs: Array<{ unit: number; delta: number | null; tradingCount: number }> = [];
	let positivePairsCount = 0;
	let negativePairsCount = 0;
	let positiveTradingAccountsCount = 0;
	let negativeTradingAccountsCount = 0;

	$: unitDeltaSummaries = Object.entries(unitGroups || {}).map(([unitStr, accounts]) => {
		const unit = parseInt(unitStr);
		const delta = computeUnitDelta(accounts);
		const tradingCount = accounts.filter(isTrading).length;
		return { unit, delta, tradingCount };
	});

	$: positivePairs = unitDeltaSummaries.filter((d) => d.delta !== null && (d.delta as number) >= 0);
	$: negativePairs = unitDeltaSummaries.filter((d) => d.delta !== null && (d.delta as number) < 0);
	$: positivePairsCount = positivePairs.length;
	$: negativePairsCount = negativePairs.length;
	$: positiveTradingAccountsCount = positivePairs.reduce((sum, d) => sum + d.tradingCount, 0);
	$: negativeTradingAccountsCount = negativePairs.reduce((sum, d) => sum + d.tradingCount, 0);

	// Count accounts with insufficient balance
	$: insufficientBalanceAccounts = summaries.filter(isInsufficientBalance);
	$: insufficientBalanceCount = insufficientBalanceAccounts.length;

	// Count accounts with low equity warning
	$: lowEquityWarningAccounts = summaries.filter(isLowEquityWarning);
	$: lowEquityWarningCount = lowEquityWarningAccounts.length;

	async function fetchData() {
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
			latestUpdate = (summaries || []).reduce((latest, a) => {
				const t = new Date(a.last_update).getTime();
				return t > latest ? t : latest;
			}, 0);
			snapshot = data.snapshot || null;
			snapshotDelta = data.snapshotDelta ?? null;
			loading = false;
		} catch (error) {
			console.error('Error fetching data:', error);
			loading = false;
		} finally {
			if (showRefreshing) {
				isRefreshing = false;
			}
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
		if (autoFetchEnabled && lastCountdown === 0 && countdownSeconds === 9 && !fetchedThisCycle) {
			fetchedThisCycle = true;
			fetchData();
		}

		// Force refresh if client time is more than 30s newer than last update
		const nowMs = now.getTime();
		const dataStale = latestUpdate > 0 && nowMs - latestUpdate > STALE_FORCE_REFRESH_MS;
		if (autoFetchEnabled && dataStale && !isRefreshing && nowMs - lastForcedRefreshAt > 5000) {
			lastForcedRefreshAt = nowMs;
			fetchedThisCycle = true;
			fetchData();
		}
		lastCountdown = countdownSeconds;
	}

	function getDataAge(timestamp: string): {
		minutes: number;
		status: 'fresh' | 'warning' | 'danger';
	} {
		const now = new Date();
		const dataTime = new Date(timestamp);
		const diffMinutes = Math.floor((now.getTime() - dataTime.getTime()) / (1000 * 60));

		if (diffMinutes >= 10) return { minutes: diffMinutes, status: 'danger' };
		if (diffMinutes >= 5) return { minutes: diffMinutes, status: 'warning' };
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

	$: wdByUnit = (() => {
		const grouped: Record<number, Array<{ account_number: string; amount: number }>> = {};
		for (const [acc, amt] of nonZeroAccountWDs) {
			const u = accountByNumber[acc]?.unit ?? 0;
			if (!grouped[u]) grouped[u] = [];
			grouped[u].push({ account_number: acc, amount: amt as number });
		}
		return grouped;
	})();

	function addUnitMapping() {
		const unitNumber = parseInt(newUnitNumber);
		if (!isNaN(unitNumber) && newUnitName.trim()) {
			unitMappings[unitNumber] = newUnitName.trim();
			updateUnitMappings();
			newUnitNumber = '';
			newUnitName = '';
		}
	}

	function removeUnitMapping(unit: number) {
		delete unitMappings[unit];
		updateUnitMappings();
	}


	function addUnitBrokerMinMargin() {
		const unit = parseInt(newUnitBrokerUnit);
		const name = newUnitBrokerName.trim();
		const margin = parseFloat(newUnitBrokerMargin);
		
		if (!isNaN(unit) && name && !isNaN(margin) && margin >= 0) {
			if (!unitBrokerMinMargins[unit]) {
				unitBrokerMinMargins[unit] = {};
			}
			unitBrokerMinMargins[unit][name] = margin;
			updateUnitBrokerMinMargins();
			newUnitBrokerUnit = '';
			newUnitBrokerName = '';
			newUnitBrokerMargin = '';
		}
	}

	function removeUnitBrokerMinMargin(unit: number, brokerName: string) {
		if (unitBrokerMinMargins[unit]) {
			delete unitBrokerMinMargins[unit][brokerName];
			if (Object.keys(unitBrokerMinMargins[unit]).length === 0) {
				delete unitBrokerMinMargins[unit];
			}
			updateUnitBrokerMinMargins();
		}
	}

	function updateUnitBrokerMargin(unit: number, oldBrokerName: string, newBrokerName: string, margin: number) {
		if (!unitBrokerMinMargins[unit]) {
			unitBrokerMinMargins[unit] = {};
		}
		
		// Remove old entry if broker name changed
		if (oldBrokerName !== newBrokerName && unitBrokerMinMargins[unit][oldBrokerName] !== undefined) {
			delete unitBrokerMinMargins[unit][oldBrokerName];
		}
		
		// Set new entry
		unitBrokerMinMargins[unit][newBrokerName] = margin;
		updateUnitBrokerMinMargins();
	}

	function getUnitDisplayName(unit: number): string {
		return unitMappings[unit] || `Unit ${unit}`;
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

	function isInsufficientBalance(account: AccountSummary): boolean {
		const min = getBrokerMinFor(account.broker_name, account.unit);
		if (min === undefined) return false;
		return account.latest_equity <= min;
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
		return ((sell.lastPositionEntryPrice as number) - (buy.lastPositionEntryPrice as number)) * 100;
	}

	// PIN Protection Functions
	function handlePinInput(digit: string) {
		if (pinInput.length < 6) {
			pinInput += digit;
			pinError = '';
		}
	}

	function clearPin() {
		pinInput = '';
		pinError = '';
	}

	function backspacePin() {
		pinInput = pinInput.slice(0, -1);
		pinError = '';
	}

	async function validatePin() {
		if (pinLoading) return;

		pinLoading = true;
		try {
			// Load PIN from Supabase if not already loaded
			if (correctPin === '250514') {
				const response = await fetch('/api/settings');
				if (response.ok) {
					const settings = await response.json();
					// For now, use hardcoded PIN since we don't have PIN API endpoint yet
					correctPin = '250514';
				}
			}

			if (pinInput === correctPin) {
				isAuthenticated = true;
				showPinModal = false;
				pinInput = '';
				pinError = '';
				persistAuth();
				// Start loading data after authentication
				await loadInitialCapital();
				await fetchData();
				startPolling();
			} else {
				pinError = 'รหัส PIN ไม่ถูกต้อง';
				pinInput = '';
			}
		} catch (error) {
			console.error('Error validating PIN:', error);
			pinError = 'เกิดข้อผิดพลาดในการตรวจสอบ PIN';
			pinInput = '';
		} finally {
			pinLoading = false;
		}
	}

	// Auto-validate when 6 digits are entered
	$: (async () => {
		if (showPinModal && !pinLoading && pinInput.length === 6) {
			// trigger validation automatically
			validatePin();
		}
	})();

	function handleKeydown(event: KeyboardEvent) {
		if (!showPinModal) return;

		const key = event.key;
		if (key >= '0' && key <= '9') {
			event.preventDefault();
			handlePinInput(key);
		} else if (key === 'Backspace') {
			event.preventDefault();
			backspacePin();
		} else if (key === 'Enter') {
			event.preventDefault();
			if (pinInput.length === 6) {
				validatePin();
			}
		} else if (key === 'Escape') {
			event.preventDefault();
			clearPin();
		}
	}

	function formatNumber(num: number): string {
		return new Intl.NumberFormat('th-TH', {
			minimumFractionDigits: 2,
			maximumFractionDigits: 2
		}).format(num);
	}

	function formatPercent(num: number): string {
		return (
			new Intl.NumberFormat('th-TH', {
				minimumFractionDigits: 2,
				maximumFractionDigits: 2
			}).format(num) + '%'
		);
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

	onMount(() => {
		// Don't load data until authenticated
		// Data loading will be triggered after PIN validation
		checkPersistedAuth();

		// Add keyboard event listener for PIN input
		document.addEventListener('keydown', handleKeydown);
		// Start 10s boundary countdown
		updateCountdown();
		countdownInterval = setInterval(updateCountdown, 1000);

		return () => {
			document.removeEventListener('keydown', handleKeydown);
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
                    unit_initial_capitals: unitInitialCapitals,
                    unit_warning_equity_percentages: unitWarningEquityPercentages,
					unit_mappings: unitMappings
				})
			});
			if (response.ok) {
				const data = await response.json();
                initialCapital = data.initial_capital;
                unitInitialCapitals = data.unit_initial_capitals || unitInitialCapitals;
                unitWarningEquityPercentages = data.unit_warning_equity_percentages || unitWarningEquityPercentages;
				// totalActiveAccounts now calculated automatically from units
				unitMappings = data.unit_mappings || unitMappings;
				// await loadInitialCapital();
				// await fetchData();
				showSettingsModal = false;
				location.reload();
			}
		} catch (e) {
			console.error('Error saving settings:', e);
		} finally {
			savingSettings = false;
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
		content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"
	/>
</svelte:head>

<!-- PIN Protection Modal -->
{#if showPinModal}
	<div class="fixed inset-0 bg-black bg-opacity-90 flex items-center justify-center z-50">
		<div class="bg-gray-800 border border-gray-600 rounded-lg shadow-2xl p-8 w-full max-w-md mx-4">
			<div class="text-center mb-6">
				<div
					class="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center mx-auto mb-4"
				>
					<svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
						/>
					</svg>
				</div>
				<h2 class="text-2xl font-bold text-white mb-2">ป้อนรหัส PIN</h2>
				<p class="text-gray-400">กรุณาป้อนรหัส PIN เพื่อเข้าใช้งานระบบ</p>
			</div>

			<!-- PIN Display -->
			<div class="flex justify-center space-x-2 mb-6">
				{#each Array(6) as _, i}
					<div
						class="w-12 h-12 border-2 border-gray-600 rounded-lg flex items-center justify-center bg-gray-700"
					>
						{#if i < pinInput.length}
							<div class="w-3 h-3 bg-blue-400 rounded-full"></div>
						{/if}
					</div>
				{/each}
			</div>

			<!-- Error Message -->
			{#if pinError}
				<div class="text-center mb-4">
					<p class="text-red-400 text-sm">{pinError}</p>
				</div>
			{/if}

			<!-- Number Pad -->
			<div class="grid grid-cols-3 gap-3 mb-6" style="touch-action: manipulation;">
				{#each ['1', '2', '3', '4', '5', '6', '7', '8', '9'] as digit}
					<button
						on:click={() => handlePinInput(digit)}
						class="w-full h-12 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors focus:ring-2 focus:ring-blue-500 focus:outline-none text-xl"
						style="touch-action: manipulation; -webkit-tap-highlight-color: transparent;"
					>
						{digit}
					</button>
				{/each}
				<button
					on:click={clearPin}
					class="w-full h-12 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors focus:ring-2 focus:ring-blue-500 focus:outline-none text-xl"
					style="touch-action: manipulation; -webkit-tap-highlight-color: transparent;"
					aria-label="Clear PIN"
				>
					<svg class="w-5 h-5 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M6 18L18 6M6 6l12 12"
						/>
					</svg>
				</button>
				<button
					on:click={() => handlePinInput('0')}
					class="w-full h-12 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors focus:ring-2 focus:ring-blue-500 focus:outline-none text-xl"
					style="touch-action: manipulation; -webkit-tap-highlight-color: transparent;"
				>
					0
				</button>
				<button
					on:click={backspacePin}
					class="w-full h-12 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors focus:ring-2 focus:ring-blue-500 focus:outline-none text-xl"
					style="touch-action: manipulation; -webkit-tap-highlight-color: transparent;"
					aria-label="Backspace"
				>
					<svg class="w-5 h-5 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M12 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2M3 12l6.414 6.414a2 2 0 001.414.586H19a2 2 0 002-2V7a2 2 0 00-2-2h-8.172a2 2 0 00-1.414.586L3 12z"
						/>
					</svg>
				</button>
			</div>

			<!-- Submit Button -->
			<button
				on:click={validatePin}
				disabled={pinInput.length !== 6 || pinLoading}
				class="w-full bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed text-white font-medium py-3 rounded-lg transition-colors focus:ring-2 focus:ring-blue-500 focus:outline-none flex items-center justify-center text-xl"
				style="touch-action: manipulation; -webkit-tap-highlight-color: transparent;"
			>
				{#if pinLoading}
					<svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" fill="none" viewBox="0 0 24 24">
						<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"
						></circle>
						<path
							class="opacity-75"
							fill="currentColor"
							d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
						></path>
					</svg>
					กำลังตรวจสอบ...
				{:else}
					เข้าสู่ระบบ
				{/if}
			</button>

			<div class="mt-4 text-center">
				<p class="text-xs text-gray-500">ใช้แป้นพิมพ์หรือคลิกปุ่มเพื่อป้อนรหัส PIN</p>
			</div>
		</div>
	</div>
{/if}

<div class="min-h-screen bg-gray-900 p-3" class:hidden={showPinModal || !appReady}>
	<div class="max-w-7xl mx-auto">
		<!-- Header -->
		<div class="mb-2">
			<div class="flex justify-between items-center mb-2">
				<!-- Settings Button (Left) -->
				<button
					on:click={() => (showSettingsModal = true)}
					class="bg-gray-700 hover:bg-gray-600 text-gray-300 hover:text-white p-2 rounded-md transition-colors"
					title="Settings"
					aria-label="Open Settings"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
						/>
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
						/>
					</svg>
				</button>

				<!-- Logout Button (Right) -->
				<button
					on:click={logout}
					class="bg-gray-700 hover:bg-gray-600 text-gray-300 hover:text-white p-2 rounded-md transition-colors"
					title="Logout"
					aria-label="Logout"
				>
					<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path
							stroke-linecap="round"
							stroke-linejoin="round"
							stroke-width="2"
							d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 11-6 0V7a3 3 0 116 0v1"
						/>
					</svg>
				</button>
			</div>
		</div>

		{#if loading}
			<div class="flex justify-center items-center h-64">
				<div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-400"></div>
			</div>
		{:else}
		<!-- Profit/Loss Highlight Card -->
		<div
			class="bg-gradient-to-r from-gray-800 to-gray-700 border border-gray-600 rounded-lg shadow-lg p-3 mb-3 text-white"
		>
			<div class="flex flex-col gap-1 md:flex-row md:items-center md:justify-between mb-2">
				<div
					class="flex flex-row flex-wrap items-center text-xs text-gray-400 gap-2 md:gap-3 md:whitespace-nowrap"
				>
					{#if latestUpdate}
						<span>Updated: {formatDateTime(new Date(latestUpdate).toISOString())}</span>
					{/if}
					<span class="flex items-center gap-1" title="Next refresh">
						<svg
							class="w-3 h-3 text-gray-300"
							fill="none"
							stroke="currentColor"
							viewBox="0 0 24 24"
							aria-hidden="true"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
							/>
						</svg>
						<span>{String(countdownSeconds).padStart(2, '0')}s</span>
					</span>
					<div
						class="flex items-center justify-between md:justify-start gap-2 w-full md:w-auto md:ml-2 mt-1 md:mt-0"
					>
						<span
							class="px-2 py-0.5 rounded-full text-xs font-semibold bg-yellow-700 border border-yellow-500 text-yellow-100"
							>Active: {stats.account_count}</span
						>
						<button
							on:click={fetchData}
							class="p-1.5 rounded-md bg-indigo-600 hover:bg-indigo-700 text-white transition-colors disabled:bg-gray-600 disabled:cursor-not-allowed ml-auto md:ml-0"
							title="Refresh"
							aria-label="Refresh"
							disabled={loading || isRefreshing}
						>
							{#if isRefreshing}
								<svg class="animate-spin w-3.5 h-3.5 text-white" fill="none" viewBox="0 0 24 24" aria-hidden="true">
									<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
									<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
								</svg>
							{:else}
								<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path
										stroke-linecap="round"
										stroke-linejoin="round"
										stroke-width="2"
										d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
									/>
								</svg>
							{/if}
						</button>
					</div>
				</div>
				<!-- Open Pairs Summary (moved inside Total Profit/Loss card) -->
				<!-- Row 1: Positive and Negative Open Points -->
				<div class="grid grid-cols-2 gap-2 mt-2">
					<div class="rounded-lg shadow-lg p-2 {positivePairs.length > 0 ? 'bg-gradient-to-br from-green-900/60 to-green-800/40' : ''}"
					>
						<h3 class="text-sm font-bold text-green-300 uppercase tracking-wide">Positive Open</h3>
						<div class="mt-1 flex flex-wrap gap-1.5">
							{#each positivePairs as d}
								<span class="inline-flex items-center justify-center min-w-7 h-6 px-1.5 rounded-full text-xs font-bold bg-green-700/60 text-green-200 shadow-sm">
									{(d.delta as number) >= 0 ? '+' : ''}{Math.round(d.delta as number)}
								</span>
							{/each}
						</div>
					</div>
					<div class="rounded-lg shadow-lg p-2 {negativePairs.length > 0 ? 'bg-gradient-to-br from-red-900/60 to-red-800/40' : ''}"
					>
						<h3 class="text-sm font-bold text-red-300 uppercase tracking-wide">Negative Open</h3>
						<div class="mt-1 flex flex-wrap gap-1.5">
							{#each negativePairs as d}
								<span class="inline-flex items-center justify-center min-w-7 h-6 px-1.5 rounded-full text-xs font-bold bg-red-700/60 text-red-200 shadow-sm">
									{Math.round(d.delta as number)}
								</span>
							{/each}
						</div>
					</div>
				</div>
				
				<!-- Row 2: Warning Boxes -->
				<div class="grid grid-cols-2 gap-2 mt-2">
					<div class="bg-gray-800 rounded-md shadow p-2 opacity-90">
						<h3 class="text-xs font-semibold text-red-300 uppercase tracking-wide">Insufficient Balance</h3>
						<div class="mt-1 flex items-center justify-between">
							<div class="flex items-center gap-1">
								<span class="text-lg font-bold text-red-400">{insufficientBalanceCount}</span>
							</div>
							{#if insufficientBalanceCount > 0}
								<div class="flex items-center gap-1">
									<svg class="w-3 h-3 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
										<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
									</svg>
									<span class="text-xs text-red-400 font-medium">Alert</span>
								</div>
							{/if}
						</div>
						{#if insufficientBalanceCount > 0}
							<div class="mt-1 text-xs text-gray-400">
								Below minimum margin requirement
							</div>
						{/if}
					</div>
                <div class="bg-gray-800  rounded-md shadow p-2 opacity-90">
						<h3 class="text-xs font-semibold text-yellow-300 uppercase tracking-wide">Low Equity Warning</h3>
						<div class="mt-1 flex items-center justify-between">
							<div class="flex items-center gap-1">
								<span class="text-lg font-bold text-yellow-400">{lowEquityWarningCount}</span>
							</div>
							{#if lowEquityWarningCount > 0}
								<div class="flex items-center gap-1">
									<svg class="w-3 h-3 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
										<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
									</svg>
									<span class="text-xs text-yellow-400 font-medium">Warning</span>
								</div>
							{/if}
						</div>
                        {#if lowEquityWarningCount > 0}
                            <div class="mt-1 text-xs text-gray-400">
                                Below unit equity threshold
                            </div>
                        {/if}
					</div>
				</div>
			</div>
			<div
				class="text-center transition-all duration-500 ease-out filter"
			>
				
				<!-- Enhanced P/L Display with prominent styling -->
		<div 
			class="bg-gradient-to-br from-gray-800/60 to-gray-700/40 rounded-xl shadow-lg p-3 mx-2"
				>
					<!-- Main P/L Percentage (emphasized) -->
							<p
						class="text-6xl font-black {!isDataComplete ? 'opacity-60' : ''}"
						class:text-green-300={adjustedProfitLossPercent >= 0}
						class:text-red-300={adjustedProfitLossPercent < 0}
					>
						{adjustedProfitLossPercent >= 0 ? '+' : ''}{formatPercent(adjustedProfitLossPercent)}
					</p>
					
					<!-- Secondary P/L Amount -->
				<div class="rounded-lg p-1 mb-2"
					>
						<p
							class="text-3xl font-black"
							class:text-green-200={adjustedProfitLoss >= 0}
							class:text-red-200={adjustedProfitLoss < 0}
						>
							{adjustedProfitLoss >= 0 ? '+' : ''}{formatNumber(adjustedProfitLoss)}
						</p>
					</div>

							{#if totalWaitingWD !== 0}
						<p class="text-sm text-gray-300 mb-2 bg-gray-700/50 rounded px-2 py-1">
							<span class="text-gray-300">
								Real P/L: {stats.profit_loss >= 0 ? '+' : ''}{formatNumber(stats.profit_loss)}
							</span>
							<span class="mx-2 text-gray-500">|</span>
							<span class="text-gray-300">
								Waiting WD: {totalWaitingWD >= 0 ? '+' : ''}{formatNumber(totalWaitingWD)}
							</span>
						</p>
					{/if}

							<!-- Snapshot delta + actions -->
							<div class="flex items-center justify-center gap-2 mt-1">
								{#if snapshot}
									<span class="text-xs px-2 py-0.5 rounded-full text-white"
										class:bg-green-800={(snapshotDelta ?? 0) >= 0}
										class:bg-red-800={(snapshotDelta ?? 0) < 0}>
										Δ vs snapshot: {(snapshotDelta ?? 0) >= 0 ? '+' : ''}{formatNumber(snapshotDelta ?? 0)} ({snapshot?.kind})
									</span>
								{/if}
								<button on:click={() => takeSnapshot('adjusted')} class="text-xs px-2 py-0.5 rounded bg-blue-600 hover:bg-blue-700 text-white disabled:bg-gray-600" disabled={snapshotLoading}>
									Snapshot
								</button>
								{#if snapshot}
									<button on:click={clearSnapshot} class="text-xs px-2 py-0.5 rounded bg-gray-600 hover:bg-gray-500 text-white disabled:bg-gray-600" disabled={snapshotLoading}>
										Clear
									</button>
								{/if}
							</div>
					
					{#if !isDataComplete}
					<div class="flex items-center justify-center gap-3">
						
							<span
								class="px-3 py-1.5 rounded-full text-sm font-bold bg-yellow-800 text-yellow-100 shadow-md"
								>⚠️ Partial Data</span
							>
					</div>
					{/if}
				</div>
			</div>
		</div>

			<!-- Account Summaries by Unit -->
		<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-2 mb-2">
			<div class="flex items-center justify-between mb-1">
					<div class="flex items-center gap-1 ml-auto">
					<button 
						on:click={collapseAllUnits}
						class="text-xs px-1.5 py-0.5 rounded bg-gray-600 hover:bg-gray-500 text-gray-200 hover:text-white border border-gray-500 transition-colors flex items-center gap-1"
							title="Collapse all unit groups"
						>
							<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
								<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
							</svg>
							Collapse All
						</button>
					<button 
						on:click={expandAllUnits}
						class="text-xs px-1.5 py-0.5 rounded bg-gray-600 hover:bg-gray-500 text-gray-200 hover:text-white border border-gray-500 transition-colors flex items-center gap-1"
							title="Expand all unit groups"
						>
							<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
								<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
							</svg>
							Expand All
						</button>
					<button on:click={() => (showFilters = !showFilters)} class="text-xs px-1.5 py-0.5 rounded bg-gray-700 text-gray-200 hover:bg-gray-600 border border-gray-600 flex items-center gap-1">
							<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
								<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
							</svg>
							{showFilters ? 'Hide Filters' : 'Show Filters'}
						</button>
					</div>
				</div>

								{#if showFilters}
				<!-- Filters: Broker / Account Name -->
			<div class="mb-2 space-y-1.5">
					<div class="flex items-center gap-1 flex-wrap">
						<span class="text-xs text-gray-400">Broker:</span>
						{#each uniqueBrokersList as b}
							<button
								on:click={() => toggleBroker(b.name)}
								class="px-1.5 py-0.5 rounded-full border text-xs transition-colors"
								class:bg-blue-600={activeBrokers.has(b.name)}
								class:text-white={activeBrokers.has(b.name)}
								class:border-blue-400={activeBrokers.has(b.name)}
								class:bg-gray-700={!activeBrokers.has(b.name)}
								class:text-gray-300={!activeBrokers.has(b.name)}
								class:border-gray-600={!activeBrokers.has(b.name)}
								title={`Toggle broker ${b.name}`}
							>
								{b.name}
								<span class="opacity-70">({b.count})</span>
							</button>
						{/each}
					<div class="ml-auto flex items-center gap-1">
						<button on:click={selectAllBrokers} class="text-xs px-1 py-0.5 rounded bg-gray-700 text-gray-200 hover:bg-gray-600">All</button>
						<button on:click={clearAllBrokers} class="text-xs px-1 py-0.5 rounded bg-gray-700 text-gray-200 hover:bg-gray-600">Clear</button>
						</div>
					</div>
					<div class="flex items-center gap-1 flex-wrap">
						<span class="text-xs text-gray-400">Account:</span>
						{#each uniqueAccountNamesList as a}
							<button
								on:click={() => toggleAccountName(a.name)}
								class="px-1.5 py-0.5 rounded-full border text-xs transition-colors"
								class:bg-blue-600={activeAccountNames.has(a.name)}
								class:text-white={activeAccountNames.has(a.name)}
								class:border-blue-400={activeAccountNames.has(a.name)}
								class:bg-gray-700={!activeAccountNames.has(a.name)}
								class:text-gray-300={!activeAccountNames.has(a.name)}
								class:border-gray-600={!activeAccountNames.has(a.name)}
								title={`Toggle account ${a.name}`}
							>
								{shortName(a.name)}
								<span class="opacity-70">({a.count})</span>
							</button>
						{/each}
					<div class="ml-auto flex items-center gap-1">
						<button on:click={selectAllAccountNames} class="text-xs px-1 py-0.5 rounded bg-gray-700 text-gray-200 hover:bg-gray-600">All</button>
						<button on:click={clearAllAccountNames} class="text-xs px-1 py-0.5 rounded bg-gray-700 text-gray-200 hover:bg-gray-600">Clear</button>
						</div>
					</div>
				</div>
				{/if}

					{#each Object.entries(unitGroups) as [unitStr, accounts]}
						{@const unit = parseInt(unitStr)}
						{@const unitStat = unitStats.find((s) => s.unit === unit)}
						{@const groupIsTrading = accounts.some(isTrading)}
						{@const sortedAccounts = [...accounts].sort(
							(a, b) =>
								a.broker_name.localeCompare(b.broker_name) ||
								a.account_number.localeCompare(b.account_number)
						)}
						{@const visibleAccounts = sortedAccounts.filter((a) => activeBrokers.has(a.broker_name) && activeAccountNames.has(a.account_name))}
						
						{#if visibleAccounts.length > 0}
						<div
							class="mb-2 rounded-md"
							class:bg-blue-700={groupIsTrading}
							class:border-2={groupIsTrading}
							class:border-blue-400={groupIsTrading}
							class:p-1={groupIsTrading}
						>
							<!-- Unit Header (always visible) -->
							<div 
							class="flex justify-between items-center mb-1 border-b border-gray-600 pb-0.5 cursor-pointer hover:bg-gray-700 hover:bg-opacity-50 rounded px-1 py-0.5 transition-colors"
								class:bg-red-950={accounts.some(isInsufficientBalance)}
								class:bg-yellow-900={!accounts.some(isInsufficientBalance) && accounts.some(isLowEquityWarning)}
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
								<div class="flex items-center space-x-1">
									<!-- Expand/Collapse Icon -->
									<svg 
										class="w-4 h-4 text-gray-400 transition-transform duration-200"
										class:rotate-90={unitVisibility[unit] !== false}
										fill="none" 
										stroke="currentColor" 
										viewBox="0 0 24 24"
									>
										<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
									</svg>
									<h3 class="text-base font-medium text-gray-200">
										{unit === 0 ? 'Unknown Unit' : getUnitDisplayName(unit)}
										{#if accounts.some(isInsufficientBalance)}
											<span class="text-red-400 font-bold ml-1" title="มีบัญชีที่เงินไม่เพียงพอในกลุ่มนี้">*</span>
										{:else if accounts.some(isLowEquityWarning)}
											<span class="text-yellow-400 font-bold ml-1" title="มีบัญชีที่ equity ต่ำกว่าเกณฑ์เตือนในกลุ่มนี้">⚠</span>
										{/if}
									</h3>
									<span class="text-xs text-gray-500 bg-gray-600 px-1 py-0.5 rounded">
										#{unit}
									</span>
									{#if computeUnitDelta(accounts) !== null}
										{@const delta = computeUnitDelta(accounts) as number}
										<span
											class="text-xs px-1 py-0.5 rounded font-semibold text-white"
											class:bg-green-600={delta >= 0}
											class:bg-red-600={delta < 0}
										>
											Open {delta > 0 ? '+' : ''}{delta.toFixed(0)} points
										</span>
									{/if}
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
											<div class="flex items-center gap-1 ml-1 flex-wrap">
												{#each nonZeroEntries as [broker, s]}
									<div class="flex items-center gap-1 bg-gray-700/40 rounded px-1 py-0.5">
										<span class="text-[10px] text-gray-200">{truncateWithEllipsis(broker, 6)}</span>
														{#if s.d > 0}
															<span class="text-[10px] px-1 rounded font-semibold bg-green-700/60 text-green-200 border border-green-500/40">D {formatNumber(s.d)}</span>
														{/if}
														{#if s.w > 0}
															<span class="text-[10px] px-1 rounded font-semibold bg-red-700/60 text-red-200 border border-red-500/40">W {formatNumber(s.w)}</span>
														{/if}
													</div>
												{/each}
											</div>
										{/if}
									{/if}
								</div>
								{#if unitStat}
									<div
										class="flex flex-col md:flex-row items-start md:items-center space-y-0.5 md:space-y-0 md:space-x-2 text-xs"
									>
										<span class="text-xs text-gray-500 bg-gray-600 px-1 py-0.5 rounded">
											Cap: {formatNumber(unitInitialCapitals[unit] ?? 0)}
										</span>
										<span class="text-gray-400">
											Total: {formatNumber(unitStat.totalBalance)}
										</span>
										<span
											class="font-medium"
											class:text-green-400={unitStat.profitLoss >= 0}
											class:text-red-400={unitStat.profitLoss < 0}
										>
											P/L: {unitStat.profitLoss >= 0 ? '+' : ''}{formatNumber(unitStat.profitLoss)}
										</span>
										{#if (unitGroups[unit] || []).reduce((s, a) => s + (accountWithdrawals[a.account_number] ?? 0), 0) > 0}
											<span class="text-gray-400">
												WD Total: {formatNumber(
													(unitGroups[unit] || []).reduce(
														(s, a) => s + (accountWithdrawals[a.account_number] ?? 0),
														0
													)
												)}
											</span>
										{/if}
									</div>
								{/if}
							</div>
							
							{#if unitVisibility[unit] !== false}
							<!-- Compact Table View -->
							<div class="overflow-x-auto">
								<table class="w-full text-xs">
									<thead>
										<tr class="border-b border-gray-600">
											<th class="text-right py-1 px-2 text-gray-400 font-medium">Adjust</th>
											<th class="text-left py-1 px-2 text-gray-400 font-medium">Account / Name</th>
											<th class="text-left py-1 px-2 text-gray-400 font-medium">Broker</th>
											<th class="text-right py-1 px-2 text-gray-400 font-medium">Balance</th>
											<th class="text-right py-1 px-2 text-gray-400 font-medium">Equity</th>
											<th class="text-right py-1 px-2 text-gray-400 font-medium">WD Note</th>
											<th class="text-left py-1 px-2 text-gray-400 font-medium">Updated</th>
										</tr>
									</thead>
									<tbody>
										{#each visibleAccounts as account}
											{@const dataAge = getDataAge(account.last_update)}
											<tr
												class="border-b border-gray-700 hover:bg-gray-600 transition-colors"
												class:bg-yellow-800={!isInsufficientBalance(account) && dataAge.status !== 'warning' && dataAge.status !== 'danger' && isLowEquityWarning(account)}
												class:bg-yellow-900={dataAge.status === 'warning'}
												class:bg-red-900={dataAge.status === 'danger'}
												class:bg-red-950={isInsufficientBalance(account)}
											>
                                            <td
													class="py-1 px-2 text-right font-medium text-xs"
                                                class:text-red-400={getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                class:text-green-400={getUnitTargetEquity(account.unit) - account.latest_equity > 0}
												>
                                                {#if getUnitTargetEquity(account.unit) - account.latest_equity > 0}
                                                    D {formatNumber(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity))}
                                                {:else if getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                    W {formatNumber(Math.abs(getUnitTargetEquity(account.unit) - account.latest_equity))}
													{:else}
														{formatNumber(0)}
													{/if}
												</td>
												<td class="py-1 px-2">
													<div class="flex flex-col leading-tight">
														<span class="font-mono font-semibold text-white text-xs">
															{#if isInsufficientBalance(account)}<span class="text-red-400">*</span>
															{/if}{account.account_number}
														</span>
														<span class="text-gray-400 text-xs truncate" title={account.account_name}
															>{shortName(account.account_name)}</span
														>
													</div>
												</td>
												<td class="py-1 px-2 text-gray-400 text-xs">{account.broker_name}</td>
												<td class="py-1 px-2 text-right font-medium text-white text-xs"
													>{formatNumber(account.latest_balance)}</td
												>
												<td class="py-1 px-2 text-right font-medium text-white text-xs"
													>{formatNumber(account.latest_equity)}</td
												>
												<td class="py-1 px-2 text-right">
													<input
														type="number"
														min="0"
														step="100"
														value={accountWithdrawals[account.account_number] ?? 0}
														on:change={(e) =>
															handleAccountWithdrawalChange(account.account_number, e)}
														class="w-20 border border-gray-600 bg-gray-700 text-white rounded px-1 py-0.5 text-right text-xs focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
													/>
												</td>
												<td class="py-1 px-2 text-gray-400 text-xs"
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

			{#if summaries.length === 0}
				<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-8">
					<div class="text-center text-gray-400">
						<svg
							class="mx-auto h-12 w-12 text-gray-500 mb-4"
							fill="none"
							viewBox="0 0 24 24"
							stroke="currentColor"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								stroke-width="2"
								d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
							/>
						</svg>
						<h3 class="text-lg font-medium text-white mb-2">No Data Available</h3>
						<p class="text-gray-300">Waiting for EA to send account data...</p>
						<p class="text-sm text-gray-500 mt-2">
							Make sure your EA is running and configured with the correct API URL.
						</p>
					</div>
				</div>
			{/if}
		{/if}
	</div>
</div>

<!-- Settings Modal -->
{#if showSettingsModal}
	<div
		class="fixed inset-0 bg-black bg-opacity-70 z-50 overflow-y-auto flex items-center justify-center p-6"
		on:click={() => (showSettingsModal = false)}
		on:keydown={(e) => e.key === 'Escape' && (showSettingsModal = false)}
		role="dialog"
		aria-modal="true"
		aria-labelledby="settings-title"
		tabindex="-1"
	>
		<div
			class="bg-gray-800 border border-gray-600 rounded-lg shadow-2xl w-full max-w-7xl mx-4 my-8 flex flex-col max-h-[85vh]"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="flex justify-between items-center p-6 pb-4">
				<h2 id="settings-title" class="text-xl font-semibold text-white">Settings</h2>
				<button
					on:click={() => (showSettingsModal = false)}
					class="text-gray-400 hover:text-gray-200 transition-colors"
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
            <div class="flex-1 overflow-y-auto px-6 pb-4 space-y-6">
                <!-- Unit Settings: Initial Capital & Warning % per unit -->
                <div>
                    <fieldset>
                        <legend class="block text-sm font-medium text-gray-300 mb-2">Unit Settings</legend>
                        <div class="space-y-2 mb-3">
                            {#each unitList as unit}
                                <div class="flex items-center justify-between bg-gray-700 border border-gray-600 rounded-md px-3 py-2">
                                    <div class="flex items-center space-x-2">
                                        <span class="text-sm font-medium text-gray-300">Unit {unit}:</span>
                                        <input
                                            type="number"
                                            min="0"
                                            step="100"
                                            value={unitInitialCapitals[unit] ?? 0}
                                            on:change={(e) => {
                                                const v = parseFloat((e.target as HTMLInputElement).value);
                                                unitInitialCapitals = { ...unitInitialCapitals, [unit]: isNaN(v) || v < 0 ? 0 : v };
                                            }}
        class="w-32 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                                        />
                                        <span class="text-sm text-gray-400">USD</span>
                                        <span class="text-sm text-gray-400">/ Warn %</span>
                                        <input
                                            type="number"
                                            min="1"
                                            max="100"
                                            step="1"
                                            value={unitWarningEquityPercentages[unit] ?? 30}
                                            on:change={(e) => {
                                                const v = parseFloat((e.target as HTMLInputElement).value);
                                                const pct = isNaN(v) || v < 1 || v > 100 ? 30 : v;
                                                unitWarningEquityPercentages = { ...unitWarningEquityPercentages, [unit]: pct };
                                            }}
        class="w-20 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                                        />
                                        <span class="text-sm text-gray-400">%</span>
                                    </div>
                                    <button
                                        on:click={() => {
                                            const nextCap = { ...unitInitialCapitals }; delete nextCap[unit]; unitInitialCapitals = nextCap;
                                            const nextWarn = { ...unitWarningEquityPercentages }; delete nextWarn[unit]; unitWarningEquityPercentages = nextWarn;
                                            // also remove mapping to fully remove this unit from settings
                                            if (unitMappings && unitMappings[unit] !== undefined) {
                                                const nextMap = { ...unitMappings }; delete nextMap[unit]; unitMappings = nextMap;
                                            }
                                        }}
                                        class="text-red-400 hover:text-red-300 transition-colors"
                                        aria-label={`Remove unit settings for unit ${unit}`}
                                    >
                                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                        </svg>
                                    </button>
                                </div>
                            {/each}
                        </div>

                        <!-- Add new unit setting -->
                        <div class="flex items-center space-x-2">
                            <input type="number" bind:value={newUnitSettingNumber} placeholder="Unit #" min="1" class="w-20 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-center focus:ring-2 focus:ring-blue-500 focus:border-blue-500" />
                            <input type="number" bind:value={newUnitSettingCap} placeholder="Initial Capital" min="0" step="100" class="w-32 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500" />
                            <span class="text-gray-400">USD</span>
                            <span class="text-gray-400">/ Warn %</span>
                            <input type="number" bind:value={newUnitSettingWarn} placeholder="%" min="1" max="100" step="1" class="w-20 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500" />
                            <button
                                on:click={addUnitSetting}
                                class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded-md text-sm transition-colors"
                                disabled={!newUnitSettingNumber || newUnitSettingCap === '' || newUnitSettingWarn === ''}
                            >
                                Add
                            </button>
                        </div>
                        <p class="text-xs text-gray-500 mt-1">Initial capital and warning threshold are set per unit. Total Initial Capital is the sum of all units.</p>
                    </fieldset>
                </div>

				<!-- Total Active Accounts now calculated automatically from units (units * 2) -->

				<!-- Unit Mappings Setting -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-gray-300 mb-2"> Unit Mappings </legend>

						<!-- Existing mappings -->
						<div class="space-y-2 mb-3">
							{#each Object.entries(unitMappings) as [unit, name]}
								<div
									class="flex items-center justify-between bg-gray-700 border border-gray-600 rounded-md px-3 py-2"
								>
									<div class="flex items-center space-x-2">
										<span class="text-sm font-medium text-gray-300">Unit {unit}:</span>
										<input
											type="text"
											value={name}
											on:change={(e) => {
												const v = (e.target as HTMLInputElement).value.trim();
												const u = parseInt(unit);
												unitMappings = { ...unitMappings, [u]: v };
												updateUnitMappings();
											}}
											class="border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
										/>
									</div>
									<button
										on:click={() => removeUnitMapping(parseInt(unit))}
										class="text-red-400 hover:text-red-300 transition-colors"
										aria-label={`Remove mapping for unit ${unit}`}
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

						<!-- Add new mapping -->
						<div class="flex items-center space-x-2">
							<input
								type="number"
								bind:value={newUnitNumber}
								placeholder="Unit #"
								class="w-20 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-center focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
								min="1"
							/>
							<span class="text-gray-400">→</span>
							<input
								type="text"
								bind:value={newUnitName}
								placeholder="Unit name"
								class="flex-1 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							/>
							<button
								on:click={addUnitMapping}
								class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded-md text-sm transition-colors"
								disabled={!newUnitNumber || !newUnitName.trim()}
							>
								Add
							</button>
						</div>
						<p class="text-xs text-gray-500 mt-1">
							Map unit numbers to descriptive names (e.g., 1 → "xs-sell")
						</p>
					</fieldset>
				</div>

				<!-- Unit-Specific Broker Min Margin Settings -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-gray-300 mb-2">
							Unit-Specific Broker Min Margin
						</legend>
						<div class="space-y-3 mb-3">
							{#each Object.entries(unitBrokerMinMargins) as [unitStr, brokerMargins]}
								{@const unit = parseInt(unitStr)}
								<div class="bg-gray-700 border border-gray-600 rounded-md">
									<div class="px-3 py-2 border-b border-gray-600 flex items-center justify-between">
										<span class="text-sm text-gray-300">Unit {unit} ({getUnitDisplayName(unit)})</span>
										<span class="text-xs text-gray-400">{Object.keys(brokerMargins).length} brokers</span>
									</div>
									<div class="divide-y divide-gray-600">
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
														class="bg-gray-600 border border-gray-500 text-gray-200 rounded px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500 min-w-0 flex-1"
													/>
													<span class="text-gray-400">=</span>
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
														class="w-24 border border-gray-600 bg-gray-700 text-white rounded px-2 py-1 text-right text-sm focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
													/>
													<span class="text-xs text-gray-300">USD</span>
												</div>
												<button
													on:click={() => removeUnitBrokerMinMargin(unit, brokerName)}
													class="text-red-400 hover:text-red-300 transition-colors ml-2"
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
							{#if Object.keys(unitBrokerMinMargins).length === 0}
								<div class="text-xs text-gray-500">No unit-specific broker margins configured.</div>
							{/if}
						</div>
						<div class="flex items-center space-x-2">
							<input
								type="number"
								bind:value={newUnitBrokerUnit}
								placeholder="Unit #"
								min="1"
								class="w-20 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-center focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							/>
							<span class="text-gray-400">→</span>
							<input
								type="text"
								bind:value={newUnitBrokerName}
								placeholder="Broker name"
								class="flex-1 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							/>
							<span class="text-gray-400">=</span>
							<input
								type="number"
								bind:value={newUnitBrokerMargin}
								placeholder="Min margin"
								min="0"
								step="100"
								class="w-32 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							/>
							<button
								on:click={addUnitBrokerMinMargin}
								disabled={!newUnitBrokerUnit || !newUnitBrokerName.trim() || !newUnitBrokerMargin}
								class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded-md text-sm transition-colors"
							>
								Add
							</button>
						</div>
						<p class="text-xs text-gray-500 mt-1">
							Set minimum margin per broker per unit. Broker names are case-insensitive. You can edit broker names directly by clicking on them.
						</p>
					</fieldset>
				</div>


				<!-- WD Notes Setting (per account) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-gray-300 mb-2"> WD Notes </legend>
						<p class="text-xs text-gray-500 mb-2">
							Set waiting withdrawal per account. Clearing the input saves as 0.
						</p>
						<div class="space-y-3 max-h-64 overflow-y-auto pr-1">
							{#each Object.entries(wdByUnit || {}) as [uStr, entries]}
								{@const u = parseInt(uStr)}
								<div class="bg-gray-700 border border-gray-600 rounded-md">
									<div class="px-3 py-2 border-b border-gray-600 flex items-center justify-between">
										<span class="text-sm text-gray-300">Unit {u === 0 ? 'Unknown' : u}</span>
										<span class="text-xs text-gray-400"
											>WD Total: {formatNumber(
												(entries || []).reduce((s, e) => s + (e.amount ?? 0), 0)
											)}</span
										>
									</div>
									<div class="divide-y divide-gray-600">
										{#each entries as e}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="text-xs text-gray-300 truncate mr-2">
													<span class="font-mono">{e.account_number}</span>
													{#if accountByNumber[e.account_number]}
														<span class="text-gray-400">
															— {shortName(accountByNumber[e.account_number].account_name)}</span
														>
													{/if}
												</div>
												<div class="flex items-center gap-2">
													<span class="text-xs text-gray-300">{formatNumber(e.amount)}</span>
													<button
														on:click={() => removeAccountWithdrawal(e.account_number)}
														class="text-red-400 hover:text-red-300 transition-colors"
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
							{#if Object.keys(wdByUnit || {}).length === 0}
								<div class="text-xs text-gray-500">No non-zero WD notes.</div>
							{/if}
						</div>
						<p class="text-xs text-gray-500 mt-1">
							Stored as mapping: account_number → amount (grouped by unit for display).
						</p>
					</fieldset>
				</div>

				<!-- Delete Account Data Section -->
				<div class="border-t border-gray-700 pt-6">
					<fieldset>
						<legend class="block text-sm font-medium text-red-400 mb-2">
							Danger Zone
						</legend>
						<div class="bg-red-900/20 border border-red-700 rounded-md p-4">
							<div class="flex items-start space-x-3">
								<svg class="w-5 h-5 text-red-400 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
								</svg>
								<div class="flex-1">
									<h4 class="text-sm font-medium text-red-300 mb-1">ลบข้อมูลบัญชีทั้งหมด</h4>
									<p class="text-xs text-red-200 mb-3">
										การดำเนินการนี้จะลบข้อมูลบัญชีทั้งหมดจาก Supabase แต่จะไม่ลบการตั้งค่าอื่นๆ เช่น Initial Capital, Unit Mappings เป็นต้น
									</p>
									<button
										on:click={() => (showDeleteConfirmModal = true)}
										class="px-3 py-1.5 rounded-md bg-red-600 hover:bg-red-700 text-white text-sm font-medium transition-colors"
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
				class="px-6 py-4 border-t border-gray-700 bg-gray-800 flex items-center justify-end gap-3"
			>
				<button
					on:click={() => (showSettingsModal = false)}
					class="px-4 py-2 rounded-md bg-gray-700 text-gray-200 hover:bg-gray-600 transition-colors"
				>
					Cancel
				</button>
				<button
					on:click={saveSettings}
					disabled={savingSettings}
					class="px-4 py-2 rounded-md bg-blue-600 text-white hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed transition-colors"
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
		class="fixed inset-0 bg-black bg-opacity-80 z-60 flex items-center justify-center p-6"
		on:click={() => (showDeleteConfirmModal = false)}
		on:keydown={(e) => e.key === 'Escape' && (showDeleteConfirmModal = false)}
		role="dialog"
		aria-modal="true"
		aria-labelledby="delete-confirm-title"
		tabindex="-1"
	>
		<div
			class="bg-gray-800 border border-red-600 rounded-lg shadow-2xl w-full max-w-md mx-4"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6">
				<div class="flex items-center mb-4">
					<div class="w-12 h-12 bg-red-600 rounded-full flex items-center justify-center mr-4">
						<svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
						</svg>
					</div>
					<div>
						<h3 id="delete-confirm-title" class="text-lg font-semibold text-white">ยืนยันการลบข้อมูล</h3>
						<p class="text-sm text-gray-400">การดำเนินการนี้ไม่สามารถย้อนกลับได้</p>
					</div>
				</div>

				<div class="mb-6">
					<p class="text-sm text-gray-300 mb-3">
						คุณแน่ใจหรือไม่ที่จะลบข้อมูลบัญชีทั้งหมดจาก Supabase?
					</p>
					<div class="bg-red-900/20 border border-red-700 rounded-md p-3">
						<p class="text-xs text-red-200">
							<strong>หมายเหตุ:</strong> การดำเนินการนี้จะลบเฉพาะข้อมูลบัญชีที่เข้ามาจาก EA เท่านั้น 
							การตั้งค่าอื่นๆ เช่น Initial Capital, Unit Mappings, WD Notes จะไม่ถูกลบ
						</p>
					</div>
				</div>

				<div class="flex items-center justify-end gap-3">
					<button
						on:click={() => (showDeleteConfirmModal = false)}
						class="px-4 py-2 rounded-md bg-gray-700 text-gray-200 hover:bg-gray-600 transition-colors"
						disabled={deletingData}
					>
						ยกเลิก
					</button>
					<button
						on:click={clearAllAccountData}
						disabled={deletingData}
						class="px-4 py-2 rounded-md bg-red-600 text-white hover:bg-red-700 disabled:bg-gray-600 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
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
