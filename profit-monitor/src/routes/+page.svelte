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

	// Count accounts with low equity warning
	$: lowEquityWarningAccounts = summaries.filter(isLowEquityWarning);
	$: lowEquityWarningCount = lowEquityWarningAccounts.length;

	// Function to check if unit has stale data
	function hasUnitStaleData(accounts: AccountSummary[]): boolean {
		return accounts.some(account => getDataAge(account.last_update).status === 'stale');
	}

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
			accountDeposits = data.accountDeposits || {};
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
			accountDeposits = data.account_deposits || {};
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

	$: wdByUnit = (() => {
		const grouped: Record<number, Array<{ account_number: string; amount: number }>> = {};
		for (const [acc, amt] of nonZeroAccountWDs) {
			const u = accountByNumber[acc]?.unit ?? 0;
			if (!grouped[u]) grouped[u] = [];
			grouped[u].push({ account_number: acc, amount: amt as number });
		}
		return grouped;
	})();

	$: dpByUnit = (() => {
		const grouped: Record<number, Array<{ account_number: string; amount: number }>> = {};
		for (const [acc, amt] of nonZeroAccountDPs) {
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
		(async () => {
			await loadInitialCapital();
			await fetchData();
			startPolling();
		})();

		updateCountdown();
		countdownInterval = setInterval(updateCountdown, 1000);

		return () => {
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
	<style>
		:root { background-color: #1c1917; }
	</style>
</svelte:head>

<div class="min-h-screen bg-stone-900" class:hidden={!appReady}>
	<!-- Sticky Top Bar -->
	<div class="sticky top-0 z-30 bg-stone-900/90 backdrop-blur-md border-b border-stone-700/50">
		<div class="max-w-7xl mx-auto px-4 py-2.5 flex items-center justify-between">
			<button
				on:click={() => (showSettingsModal = true)}
				class="text-stone-500 hover:text-stone-300 p-1.5 rounded-lg hover:bg-stone-800 transition-colors"
				title="Settings"
				aria-label="Open Settings"
			>
				<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
				</svg>
			</button>

			<div class="flex items-center gap-2 text-xs text-stone-500">
				{#if latestUpdate}
					<span>{formatDateTime(new Date(latestUpdate).toISOString())}</span>
				{/if}
				<span class="flex items-center gap-0.5" title="Next refresh">
					<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg>
					{String(countdownSeconds).padStart(2, '0')}s
				</span>
				<button
					on:click={fetchData}
					class="p-1 rounded-md bg-indigo-500 hover:bg-indigo-600 text-white transition-colors disabled:bg-stone-700 disabled:cursor-not-allowed"
					title="Refresh"
					aria-label="Refresh"
					disabled={loading || isRefreshing}
				>
					{#if isRefreshing}
						<svg class="animate-spin w-3.5 h-3.5" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>
					{:else}
						<svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" /></svg>
					{/if}
				</button>
			</div>

		</div>
	</div>

	<div class="max-w-7xl mx-auto px-4 py-4 space-y-4">
		{#if loading}
			<div class="flex justify-center items-center h-64">
				<div class="animate-spin rounded-full h-10 w-10 border-2 border-indigo-500 border-t-transparent"></div>
			</div>
		{:else}

		<!-- Hero P/L -->
		<div class="text-center pt-2 pb-4">
			{#if !isDataComplete}
				<span class="inline-block px-2.5 py-0.5 rounded-full text-xs font-semibold bg-amber-900/40 border border-amber-700/50 text-amber-400 mb-2">Partial Data</span>
			{/if}
			<p
				class="text-5xl md:text-7xl font-black tracking-tight leading-none {!isDataComplete ? 'opacity-60' : ''}"
				class:text-emerald-500={adjustedProfitLoss >= 0}
				class:text-red-500={adjustedProfitLoss < 0}
			>
				{adjustedProfitLoss >= 0 ? '+' : ''}{formatNumber(adjustedProfitLoss)}
			</p>
			<p
				class="text-xl md:text-2xl font-semibold mt-1 tracking-tight"
				class:text-emerald-400={adjustedProfitLossPercent >= 0}
				class:text-red-400={adjustedProfitLossPercent < 0}
			>
				{adjustedProfitLossPercent >= 0 ? '+' : ''}{formatPercent(adjustedProfitLossPercent)}
			</p>

			{#if totalWaitingWD !== 0 || totalDeposits !== 0}
				<div class="flex items-center justify-center gap-3 mt-2 text-xs text-stone-500">
					<span>Total P/L: {stats.profit_loss >= 0 ? '+' : ''}{formatNumber(stats.profit_loss)}</span>
					{#if totalWaitingWD !== 0}
						<span>WD: {totalWaitingWD >= 0 ? '+' : ''}{formatNumber(totalWaitingWD)}</span>
					{/if}
					{#if totalDeposits !== 0}
						<span>DP: -{formatNumber(totalDeposits)}</span>
					{/if}
				</div>
			{/if}

			<!-- Snapshot -->
			<div class="flex items-center justify-center gap-2 mt-2.5">
				{#if snapshot}
					<span class="text-xs px-2 py-0.5 rounded-full text-white"
						class:bg-emerald-500={(snapshotDelta ?? 0) >= 0}
						class:bg-red-500={(snapshotDelta ?? 0) < 0}>
						Δ {(snapshotDelta ?? 0) >= 0 ? '+' : ''}{formatNumber(snapshotDelta ?? 0)}
					</span>
				{/if}
				<button on:click={() => takeSnapshot('adjusted')} class="text-xs px-2.5 py-1 rounded-lg bg-stone-800 hover:bg-stone-700 text-stone-400 transition-colors disabled:opacity-50" disabled={snapshotLoading}>
					Snapshot
				</button>
				{#if snapshot}
					<button on:click={clearSnapshot} class="text-xs px-2.5 py-1 rounded-lg bg-stone-800 hover:bg-stone-700 text-stone-400 transition-colors disabled:opacity-50" disabled={snapshotLoading}>
						Clear
					</button>
				{/if}
			</div>
		</div>

		<!-- Stats Grid: 3 metric cards -->
		<div class="grid grid-cols-3 gap-3">
			<!-- Active Accounts -->
			<div class="bg-stone-800 rounded-2xl border border-stone-700/50 shadow-sm p-3">
				<div class="text-xs font-medium text-stone-500 uppercase tracking-wider">Active</div>
				<div class="text-2xl font-bold text-stone-200 mt-0.5">{stats.account_count}</div>
			</div>

			<!-- Open Pairs -->
			<div class="bg-stone-800 rounded-2xl border border-stone-700/50 shadow-sm p-3">
				<div class="text-xs font-medium text-stone-500 uppercase tracking-wider">Open Pairs</div>
				<div class="flex items-baseline gap-2 mt-0.5">
					<span class="text-2xl font-bold text-stone-200">{tradingPairs}</span>
					{#if positivePairsCount > 0 || negativePairsCount > 0}
						<span class="text-xs">
							<span class="text-emerald-500 font-semibold">+{positivePairsCount}</span>
							<span class="text-stone-500 mx-0.5">/</span>
							<span class="text-red-500 font-semibold">-{negativePairsCount}</span>
						</span>
					{/if}
				</div>
			</div>

			<!-- Low Equity Warning -->
			<div class="rounded-2xl border shadow-sm p-3 {lowEquityWarningCount > 0 ? 'bg-red-900/30 border-red-800/50' : 'bg-stone-800 border-stone-700/50'}">
				<div class="text-xs font-medium uppercase tracking-wider {lowEquityWarningCount > 0 ? 'text-red-400' : 'text-stone-500'}">Low Equity</div>
				<div class="text-2xl font-bold mt-0.5 {lowEquityWarningCount > 0 ? 'text-red-400' : 'text-stone-200'}">{lowEquityWarningCount}</div>
			</div>
		</div>

		<!-- Open Pairs Detail -->
		{#if positivePairs.length > 0 || negativePairs.length > 0}
		<div class="grid grid-cols-2 gap-3">
			<div class="bg-stone-800 rounded-2xl border border-stone-700/50 shadow-sm p-3">
				<div class="text-xs font-medium text-emerald-400 uppercase tracking-wider mb-1.5">Positive Open</div>
				<div class="flex flex-wrap gap-1.5">
					{#each positivePairs as d}
						<span class="inline-flex items-center justify-center min-w-7 h-6 px-1.5 rounded-lg text-xs font-bold bg-emerald-900/40 text-emerald-400 border border-emerald-800/50">
							+{Math.round(d.delta as number)}
						</span>
					{/each}
					{#if positivePairs.length === 0}
						<span class="text-xs text-stone-600">--</span>
					{/if}
				</div>
			</div>
			<div class="bg-stone-800 rounded-2xl border border-stone-700/50 shadow-sm p-3">
				<div class="text-xs font-medium text-red-400 uppercase tracking-wider mb-1.5">Negative Open</div>
				<div class="flex flex-wrap gap-1.5">
					{#each negativePairs as d}
						<span class="inline-flex items-center justify-center min-w-7 h-6 px-1.5 rounded-lg text-xs font-bold bg-red-900/40 text-red-400 border border-red-800/50">
							{Math.round(d.delta as number)}
						</span>
					{/each}
					{#if negativePairs.length === 0}
						<span class="text-xs text-stone-600">--</span>
					{/if}
				</div>
			</div>
		</div>
		{/if}

		<!-- Toolbar -->
		<div class="flex items-center justify-between">
			<div class="flex items-center gap-1.5">
				<button 
					on:click={collapseAllUnits}
					class="text-xs px-2.5 py-1.5 rounded-lg bg-stone-800 hover:bg-stone-700 text-stone-400 hover:text-stone-300 transition-colors border border-stone-700/50 shadow-sm flex items-center gap-1"
					title="Collapse all unit groups"
				>
					<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" /></svg>
					Collapse
				</button>
				<button 
					on:click={expandAllUnits}
					class="text-xs px-2.5 py-1.5 rounded-lg bg-stone-800 hover:bg-stone-700 text-stone-400 hover:text-stone-300 transition-colors border border-stone-700/50 shadow-sm flex items-center gap-1"
					title="Expand all unit groups"
				>
					<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" /></svg>
					Expand
				</button>
			</div>
			<button on:click={() => (showFilters = !showFilters)} class="text-xs px-2.5 py-1.5 rounded-lg bg-stone-800 hover:bg-stone-700 text-stone-400 hover:text-stone-300 transition-colors border border-stone-700/50 shadow-sm flex items-center gap-1">
				<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" /></svg>
				{showFilters ? 'Hide Filters' : 'Filters'}
			</button>
		</div>

		{#if showFilters}
		<div class="bg-stone-800 rounded-2xl border border-stone-700/50 shadow-sm p-3 space-y-2">
			<div class="flex items-center gap-1.5 flex-wrap">
				<span class="text-xs text-stone-500 font-medium">Broker:</span>
				{#each uniqueBrokersList as b}
					<button
						on:click={() => toggleBroker(b.name)}
						class="px-2 py-0.5 rounded-full border text-xs transition-colors"
						class:bg-indigo-500={activeBrokers.has(b.name)}
						class:text-white={activeBrokers.has(b.name)}
						class:border-indigo-400={activeBrokers.has(b.name)}
						class:bg-stone-700={!activeBrokers.has(b.name)}
						class:text-stone-400={!activeBrokers.has(b.name)}
						class:border-stone-600={!activeBrokers.has(b.name)}
						title={`Toggle broker ${b.name}`}
					>
						{b.name} <span class="opacity-60">({b.count})</span>
					</button>
				{/each}
				<div class="ml-auto flex items-center gap-1">
					<button on:click={selectAllBrokers} class="text-xs px-1.5 py-0.5 rounded-md text-stone-500 hover:text-stone-300 hover:bg-stone-700">All</button>
					<button on:click={clearAllBrokers} class="text-xs px-1.5 py-0.5 rounded-md text-stone-500 hover:text-stone-300 hover:bg-stone-700">Clear</button>
				</div>
			</div>
			<div class="flex items-center gap-1.5 flex-wrap">
				<span class="text-xs text-stone-500 font-medium">Account:</span>
				{#each uniqueAccountNamesList as a}
					<button
						on:click={() => toggleAccountName(a.name)}
						class="px-2 py-0.5 rounded-full border text-xs transition-colors"
						class:bg-indigo-500={activeAccountNames.has(a.name)}
						class:text-white={activeAccountNames.has(a.name)}
						class:border-indigo-400={activeAccountNames.has(a.name)}
						class:bg-stone-700={!activeAccountNames.has(a.name)}
						class:text-stone-400={!activeAccountNames.has(a.name)}
						class:border-stone-600={!activeAccountNames.has(a.name)}
						title={`Toggle account ${a.name}`}
					>
						{shortName(a.name)} <span class="opacity-60">({a.count})</span>
					</button>
				{/each}
				<div class="ml-auto flex items-center gap-1">
					<button on:click={selectAllAccountNames} class="text-xs px-1.5 py-0.5 rounded-md text-stone-500 hover:text-stone-300 hover:bg-stone-700">All</button>
					<button on:click={clearAllAccountNames} class="text-xs px-1.5 py-0.5 rounded-md text-stone-500 hover:text-stone-300 hover:bg-stone-700">Clear</button>
				</div>
			</div>
		</div>
		{/if}

		<!-- Unit Groups -->
		<div class="space-y-3">

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
						{@const unitHasStaleData = hasUnitStaleData(visibleAccounts)}
						
						{#if visibleAccounts.length > 0}
						<div
							class="bg-stone-800 rounded-2xl border shadow-sm overflow-hidden {groupIsTrading ? 'border-indigo-700/50' : 'border-stone-700/50'}"
						>
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
											class="w-3.5 h-3.5 text-stone-500 transition-transform duration-200 flex-shrink-0"
											class:rotate-90={unitVisibility[unit] !== false}
											fill="none" stroke="currentColor" viewBox="0 0 24 24"
										>
											<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
										</svg>
										<h3 class="text-sm font-semibold text-stone-200">
											{unit === 0 ? 'Unknown Unit' : getUnitDisplayName(unit)}
										</h3>
										<span class="text-[10px] text-stone-500">#{unit}</span>
										{#if accounts.some(isLowEquityWarning)}
											<span class="w-1.5 h-1.5 rounded-full bg-red-400 flex-shrink-0" title="Low equity"></span>
										{/if}
										{#if unitHasStaleData}
											<span class="w-1.5 h-1.5 rounded-full bg-orange-400 flex-shrink-0" title="Stale data"></span>
										{/if}
										{#if unitStat}
											{#if Math.abs(unitStat.profitLoss) >= 0.01}
												<button on:click|stopPropagation={() => adjustUnitPLToZero(unit)} disabled={adjustingPLUnits.has(unit)} class="text-[10px] px-1.5 py-0.5 rounded font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
													{adjustingPLUnits.has(unit) ? '...' : 'Set P/L Zero'}
												</button>
											{/if}
											{#if isGroupNotNetted(unitGroups[unit] || [])}
												<button on:click|stopPropagation={() => consolidateGroupWDDP(unit)} disabled={consolidatingUnits.has(unit)} class="text-[10px] px-1.5 py-0.5 rounded font-medium bg-cyan-900/40 hover:bg-cyan-900/60 text-cyan-400 disabled:opacity-50 transition-colors">
													{consolidatingUnits.has(unit) ? '...' : 'Simplify WD/DP'}
												</button>
											{/if}
										{/if}
									</div>
									<div class="flex items-center gap-1.5 flex-shrink-0">
										{#if computeUnitDelta(accounts) !== null}
											{@const delta = computeUnitDelta(accounts) as number}
											<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold {delta >= 0 ? 'bg-emerald-900/40 text-emerald-400' : 'bg-red-900/40 text-red-400'}">
												{delta > 0 ? '+' : ''}{delta.toFixed(0)} pts
											</span>
										{/if}
										{#if true}
											{@const accountWithPosition = visibleAccounts.find(a => (a.lastSize || 0) > 0)}
											{@const positionLots = accountWithPosition?.lastSize || 0}
											{#if positionLots > 0}
												<span class="text-xs px-1.5 py-0.5 rounded-md font-semibold bg-violet-900/40 text-violet-400">
													{positionLots.toFixed(2)}L
												</span>
											{/if}
										{/if}
									</div>
								</div>

								<!-- Row 2: Stats line + P/L -->
								{#if unitStat}
									<div class="flex items-center justify-between mt-1.5">
										<div class="flex items-center gap-x-3 gap-y-0.5 flex-wrap text-xs text-stone-500">
											<span>C: {formatNumber(unitInitialCapitals[unit] ?? 0)}</span>
											<span>T: {formatNumber(unitStat.totalBalance)}</span>
											{#if (unitGroups[unit] || []).reduce((s, a) => s + (accountWithdrawals[a.account_number] ?? 0), 0) > 0}
												<span>WD: +{formatNumber((unitGroups[unit] || []).reduce((s, a) => s + (accountWithdrawals[a.account_number] ?? 0), 0))}</span>
											{/if}
											{#if (unitGroups[unit] || []).reduce((s, a) => s + (accountDeposits[a.account_number] ?? 0), 0) > 0}
												<span>DP: -{formatNumber((unitGroups[unit] || []).reduce((s, a) => s + (accountDeposits[a.account_number] ?? 0), 0))}</span>
											{/if}
										</div>
										<span class="text-xs font-semibold flex-shrink-0 ml-3" class:text-emerald-400={unitStat.profitLoss >= 0} class:text-red-400={unitStat.profitLoss < 0}>
											{unitStat.profitLoss >= 0 ? '+' : ''}{formatNumber(unitStat.profitLoss)}{#if unitInitialCapitals[unit] && unitInitialCapitals[unit] > 0} <span class="font-normal text-stone-500">({((unitStat.profitLoss / unitInitialCapitals[unit]) * 100).toFixed(1)}%)</span>{/if}
										</span>
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
													<span class="text-stone-500">{truncateWithEllipsis(broker, 6)}</span>
													{#if s.d > 0}<span class="text-emerald-400 font-medium">D{formatNumber(s.d)}</span>{/if}
													{#if s.w > 0}<span class="text-red-400 font-medium">W{formatNumber(s.w)}</span>{/if}
												</div>
											{/each}
										</div>
									{/if}
								{/if}
							</div>
							
							{#if unitVisibility[unit] !== false}
							<!-- Compact Table View -->
							<div class="overflow-x-auto px-1">
								<table class="w-full text-xs">
									<thead>
										<tr class="border-b border-stone-700">
											<th class="text-right py-1.5 px-2 text-stone-500 font-medium">Adjust</th>
											<th class="text-left py-1.5 px-2 text-stone-500 font-medium">Account / Name</th>
											<th class="text-left py-1.5 px-2 text-stone-500 font-medium">Broker</th>
											<th class="text-right py-1.5 px-2 text-stone-500 font-medium">Balance</th>
											<th class="text-right py-1.5 px-2 text-stone-500 font-medium">Equity</th>
											<th class="text-right py-1.5 px-2 text-stone-500 font-medium">WD Note (+)</th>
											<th class="text-right py-1.5 px-2 text-stone-500 font-medium">DP Note (-)</th>
											<th class="text-center py-1.5 px-2 text-stone-500 font-medium">Status</th>
											<th class="text-left py-1.5 px-2 text-stone-500 font-medium">Updated</th>
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
                                                class:text-red-400={getUnitTargetEquity(account.unit) - account.latest_equity < 0}
                                                class:text-emerald-400={getUnitTargetEquity(account.unit) - account.latest_equity > 0}
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
														<span class="font-mono font-semibold text-stone-200 text-xs">
															{account.account_number}
														</span>
														<span class="text-stone-500 text-xs truncate" title={account.account_name}
															>{shortName(account.account_name)}</span
														>
													</div>
												</td>
												<td class="py-1.5 px-2 text-stone-500 text-xs">{account.broker_name}</td>
												<td class="py-1.5 px-2 text-right font-medium text-stone-200 text-xs"
													>{formatNumber(account.latest_balance)}</td
												>
												<td class="py-1.5 px-2 text-right font-medium text-stone-200 text-xs"
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
														class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-md px-1.5 py-0.5 text-right text-xs focus:ring-1 focus:ring-indigo-400 focus:border-indigo-400"
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
														class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-md px-1.5 py-0.5 text-right text-xs focus:ring-1 focus:ring-indigo-400 focus:border-indigo-400"
													/>
												</td>
												<td class="py-1.5 px-2 text-center">
													{#if dataAge.status === 'stale'}
														<span class="text-orange-500 font-bold" title="ข้อมูลเก่ากว่า 5 นาที ({dataAge.minutes} นาที)">
															~
														</span>
													{:else}
														<span class="text-emerald-500" title="ข้อมูลใหม่">
															✓
														</span>
													{/if}
												</td>
												<td class="py-1.5 px-2 text-stone-500 text-xs"
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
			<div class="bg-indigo-950/40 rounded-2xl border border-indigo-800/40 shadow-sm px-4 py-3">
				<div class="flex items-center justify-between">
					<div class="flex flex-col">
						<span class="text-xs font-medium text-indigo-400 uppercase tracking-wider">Total</span>
						{#if initialCapital > 0}
							<span class="text-[10px] text-stone-500 mt-0.5">Capital: {formatNumber(initialCapital)}</span>
						{/if}
					</div>
					<div class="flex items-center gap-2">
						<span class="text-lg font-bold text-stone-200">
							{formatNumber(unitStats.reduce((sum, s) => sum + s.totalBalance, 0))}
						</span>
						{#if unitStats.some((s) => Math.abs(s.profitLoss) >= 0.01)}
							<button on:click={adjustAllGroupsPL} disabled={adjustingAllPL} class="text-[10px] px-2 py-0.5 rounded-md font-medium bg-amber-900/40 hover:bg-amber-900/60 text-amber-400 disabled:opacity-50 transition-colors">
								{adjustingAllPL ? '...' : 'Set P/L Zero All'}
							</button>
						{/if}
						{#if Object.values(unitGroups).some((accs) => isGroupNotNetted(accs))}
							<button on:click={consolidateAllGroupsWDDP} disabled={consolidatingAll} class="text-[10px] px-2 py-0.5 rounded-md font-medium bg-cyan-900/40 hover:bg-cyan-900/60 text-cyan-400 disabled:opacity-50 transition-colors">
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
									class="w-full flex items-center justify-between text-xs text-stone-400 bg-stone-800/60 hover:bg-stone-700/60 rounded-lg px-2.5 py-1.5 transition-colors"
								>
									<span class="flex items-center gap-1.5">
										<svg class="w-3 h-3 text-stone-500 transition-transform {expandedBrokers.has(broker) ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" /></svg>
										{broker}
										<span class="text-[10px] text-stone-500">({Object.keys(brokerData.names).length})</span>
									</span>
									<span class="font-semibold text-stone-300">{formatNumber(brokerData.equity)}</span>
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
														class="w-full flex items-center justify-between text-[11px] text-stone-400 hover:bg-stone-700/40 rounded-md px-2.5 py-1 transition-colors"
													>
														<span class="flex items-center gap-1.5">
															<svg class="w-2.5 h-2.5 text-stone-500 transition-transform {expandedBrokerNames.has(nameKey) ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" /></svg>
															<span class="truncate">{name}</span>
															<span class="text-[10px] text-stone-500">({nameData.accounts.length})</span>
														</span>
														<span class="font-medium text-stone-300 whitespace-nowrap">{formatNumber(nameData.equity)}</span>
													</button>
													{#if expandedBrokerNames.has(nameKey)}
														<div class="ml-5 mt-0.5 space-y-0.5">
															{#each nameData.accounts.sort((a, b) => b.equity - a.equity) as acct}
																<div class="flex items-center justify-between text-[10px] px-2.5 py-0.5 rounded bg-stone-800/40">
																	<span class="text-stone-500 tabular-nums">{acct.number}</span>
																	<span class="font-medium text-stone-400 whitespace-nowrap">{formatNumber(acct.equity)}</span>
																</div>
															{/each}
														</div>
													{/if}
												{:else}
													<!-- Single account under this name — show inline -->
													<div class="flex items-center justify-between text-[11px] text-stone-400 px-2.5 py-1 rounded-md">
														<span class="flex items-center gap-1.5">
															<span class="w-2.5"></span>
															<span class="truncate">{name}</span>
															<span class="text-[10px] text-stone-500">{nameData.accounts[0].number}</span>
														</span>
														<span class="font-medium text-stone-300 whitespace-nowrap">{formatNumber(nameData.equity)}</span>
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
			<div class="bg-stone-800 border border-stone-700/50 rounded-2xl shadow-sm p-12 text-center">
				<svg class="mx-auto h-10 w-10 text-stone-600 mb-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
					<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
				</svg>
				<h3 class="text-base font-medium text-stone-300 mb-1">No Data Available</h3>
				<p class="text-sm text-stone-500">Waiting for EA to send account data...</p>
			</div>
		{/if}

		{/if}
	</div>
</div>

<!-- Settings Modal -->
{#if showSettingsModal}
	<div
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 overflow-y-auto flex items-center justify-center p-6"
		on:click={() => (showSettingsModal = false)}
		on:keydown={(e) => e.key === 'Escape' && (showSettingsModal = false)}
		role="dialog"
		aria-modal="true"
		aria-labelledby="settings-title"
		tabindex="-1"
	>
		<div
			class="bg-stone-800 rounded-2xl shadow-xl w-full max-w-7xl mx-4 my-8 flex flex-col max-h-[85vh] border border-stone-700"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="flex justify-between items-center p-6 pb-4">
				<h2 id="settings-title" class="text-xl font-semibold text-stone-200">Settings</h2>
				<button
					on:click={() => (showSettingsModal = false)}
					class="text-stone-500 hover:text-stone-300 transition-colors"
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
                        <legend class="block text-sm font-medium text-stone-300 mb-2">Unit Settings</legend>
                        <div class="space-y-2 mb-3">
                            {#each unitList as unit}
                                <div class="flex items-center justify-between bg-stone-700/50 border border-stone-600 rounded-xl px-3 py-2">
                                    <div class="flex items-center space-x-2">
                                        <span class="text-sm font-medium text-stone-400">Unit {unit}:</span>
                                        <input
                                            type="number"
                                            min="0"
                                            step="100"
                                            value={unitInitialCapitals[unit] ?? 0}
                                            on:change={(e) => {
                                                const v = parseFloat((e.target as HTMLInputElement).value);
                                                unitInitialCapitals = { ...unitInitialCapitals, [unit]: isNaN(v) || v < 0 ? 0 : v };
                                            }}
        class="w-32 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
                                        />
                                        <span class="text-sm text-stone-500">USD</span>
                                        <span class="text-sm text-stone-500">/ Warn %</span>
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
        class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
                                        />
                                        <span class="text-sm text-stone-500">%</span>
                                    </div>
                                    <button
                                        on:click={() => {
                                            const nextCap = { ...unitInitialCapitals }; delete nextCap[unit]; unitInitialCapitals = nextCap;
                                            const nextWarn = { ...unitWarningEquityPercentages }; delete nextWarn[unit]; unitWarningEquityPercentages = nextWarn;
                                            if (unitMappings && unitMappings[unit] !== undefined) {
                                                const nextMap = { ...unitMappings }; delete nextMap[unit]; unitMappings = nextMap;
                                            }
                                        }}
                                        class="text-red-400 hover:text-red-500 transition-colors"
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
                            <input type="number" bind:value={newUnitSettingNumber} placeholder="Unit #" min="1" class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-center focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400" />
                            <input type="number" bind:value={newUnitSettingCap} placeholder="Initial Capital" min="0" step="100" class="w-32 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400" />
                            <span class="text-stone-500">USD</span>
                            <span class="text-stone-500">/ Warn %</span>
                            <input type="number" bind:value={newUnitSettingWarn} placeholder="%" min="1" max="100" step="1" class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400" />
                            <button
                                on:click={addUnitSetting}
                                class="bg-indigo-500 hover:bg-indigo-600 text-white px-3 py-1 rounded-lg text-sm transition-colors"
                                disabled={!newUnitSettingNumber || newUnitSettingCap === '' || newUnitSettingWarn === ''}
                            >
                                Add
                            </button>
                        </div>
                        <p class="text-xs text-stone-500 mt-1">Initial capital and warning threshold are set per unit. Total Initial Capital is the sum of all units.</p>
                    </fieldset>
                </div>

				<!-- Total Active Accounts now calculated automatically from units (units * 2) -->

				<!-- Unit Mappings Setting -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-stone-300 mb-2"> Unit Mappings </legend>

						<!-- Existing mappings -->
						<div class="space-y-2 mb-3">
							{#each Object.entries(unitMappings) as [unit, name]}
								<div
									class="flex items-center justify-between bg-stone-700/50 border border-stone-600 rounded-xl px-3 py-2"
								>
									<div class="flex items-center space-x-2">
										<span class="text-sm font-medium text-stone-400">Unit {unit}:</span>
										<input
											type="text"
											value={name}
											on:change={(e) => {
												const v = (e.target as HTMLInputElement).value.trim();
												const u = parseInt(unit);
												unitMappings = { ...unitMappings, [u]: v };
												updateUnitMappings();
											}}
											class="border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
										/>
									</div>
									<button
										on:click={() => removeUnitMapping(parseInt(unit))}
										class="text-red-400 hover:text-red-500 transition-colors"
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
								class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-center focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
								min="1"
							/>
							<span class="text-stone-500">→</span>
							<input
								type="text"
								bind:value={newUnitName}
								placeholder="Unit name"
								class="flex-1 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
							/>
							<button
								on:click={addUnitMapping}
								class="bg-indigo-500 hover:bg-indigo-600 text-white px-3 py-1 rounded-lg text-sm transition-colors"
								disabled={!newUnitNumber || !newUnitName.trim()}
							>
								Add
							</button>
						</div>
						<p class="text-xs text-stone-500 mt-1">
							Map unit numbers to descriptive names (e.g., 1 → "xs-sell")
						</p>
					</fieldset>
				</div>

				<!-- Unit-Specific Broker Min Margin Settings -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-stone-300 mb-2">
							Unit-Specific Broker Min Margin
						</legend>
						<div class="space-y-3 mb-3">
							{#each Object.entries(unitBrokerMinMargins) as [unitStr, brokerMargins]}
								{@const unit = parseInt(unitStr)}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-stone-300">Unit {unit} ({getUnitDisplayName(unit)})</span>
										<span class="text-xs text-stone-500">{Object.keys(brokerMargins).length} brokers</span>
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
														class="bg-stone-700 border border-stone-600 text-stone-200 rounded-lg px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-indigo-400 focus:border-indigo-400 min-w-0 flex-1"
													/>
						<span class="text-stone-500">=</span>
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
														class="w-24 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right text-sm focus:ring-1 focus:ring-indigo-400 focus:border-indigo-400"
													/>
													<span class="text-xs text-stone-500">USD</span>
												</div>
												<button
													on:click={() => removeUnitBrokerMinMargin(unit, brokerName)}
													class="text-red-400 hover:text-red-500 transition-colors ml-2"
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
								<div class="text-xs text-stone-500">No unit-specific broker margins configured.</div>
							{/if}
						</div>
						<div class="flex items-center space-x-2">
							<input
								type="number"
								bind:value={newUnitBrokerUnit}
								placeholder="Unit #"
								min="1"
								class="w-20 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-center focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
							/>
							<span class="text-stone-500">→</span>
							<input
								type="text"
								bind:value={newUnitBrokerName}
								placeholder="Broker name"
								class="flex-1 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
							/>
							<span class="text-stone-500">=</span>
							<input
								type="number"
								bind:value={newUnitBrokerMargin}
								placeholder="Min margin"
								min="0"
								step="100"
								class="w-32 border border-stone-600 bg-stone-700 text-stone-200 rounded-lg px-2 py-1 text-right focus:ring-2 focus:ring-indigo-400 focus:border-indigo-400"
							/>
							<button
								on:click={addUnitBrokerMinMargin}
								disabled={!newUnitBrokerUnit || !newUnitBrokerName.trim() || !newUnitBrokerMargin}
								class="bg-indigo-500 hover:bg-indigo-600 text-white px-3 py-1 rounded-lg text-sm transition-colors"
							>
								Add
							</button>
						</div>
						<p class="text-xs text-stone-500 mt-1">
							Set minimum margin per broker per unit. Broker names are case-insensitive. You can edit broker names directly by clicking on them.
						</p>
					</fieldset>
				</div>


				<!-- WD Notes Setting (per account) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-stone-300 mb-2"> WD Notes </legend>
						<p class="text-xs text-stone-500 mb-2">
							Set waiting withdrawal per account. Clearing the input saves as 0.
						</p>
						<div class="space-y-3 max-h-64 overflow-y-auto pr-1">
							{#each Object.entries(wdByUnit || {}) as [uStr, entries]}
								{@const u = parseInt(uStr)}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-stone-300">Unit {u === 0 ? 'Unknown' : u}</span>
										<span class="text-xs text-stone-500"
											>WD Total: {formatNumber(
												(entries || []).reduce((s, e) => s + (e.amount ?? 0), 0)
											)}</span
										>
									</div>
									<div class="divide-y divide-stone-600/50">
										{#each entries as e}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="text-xs text-stone-400 truncate mr-2">
													<span class="font-mono">{e.account_number}</span>
													{#if accountByNumber[e.account_number]}
														<span class="text-stone-500">
															— {shortName(accountByNumber[e.account_number].account_name)}</span
														>
													{/if}
												</div>
												<div class="flex items-center gap-2">
													<span class="text-xs text-stone-400">{formatNumber(e.amount)}</span>
													<button
														on:click={() => removeAccountWithdrawal(e.account_number)}
														class="text-red-400 hover:text-red-500 transition-colors"
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
								<div class="text-xs text-stone-500">No non-zero WD notes.</div>
							{/if}
						</div>
						<p class="text-xs text-stone-500 mt-1">
							Stored as mapping: account_number → amount (grouped by unit for display).
						</p>
					</fieldset>
				</div>

				<!-- DP Notes Setting (per account) -->
				<div>
					<fieldset>
						<legend class="block text-sm font-medium text-stone-300 mb-2"> DP Notes </legend>
						<p class="text-xs text-stone-500 mb-2">
							Set deposit adjustment per account. This will reduce P/L calculation.
						</p>
						<div class="space-y-3 max-h-64 overflow-y-auto pr-1">
							{#each Object.entries(dpByUnit || {}) as [uStr, entries]}
								{@const u = parseInt(uStr)}
								<div class="bg-stone-700/50 border border-stone-600 rounded-xl">
									<div class="px-3 py-2 border-b border-stone-600 flex items-center justify-between">
										<span class="text-sm text-stone-300">Unit {u === 0 ? 'Unknown' : u}</span>
										<span class="text-xs text-stone-500"
											>DP Total: {formatNumber(
												(entries || []).reduce((s, e) => s + (e.amount ?? 0), 0)
											)}</span
										>
									</div>
									<div class="divide-y divide-stone-600/50">
										{#each entries as e}
											<div class="flex items-center justify-between px-3 py-2">
												<div class="text-xs text-stone-400 truncate mr-2">
													<span class="font-mono">{e.account_number}</span>
													{#if accountByNumber[e.account_number]}
														<span class="text-stone-500">
															— {shortName(accountByNumber[e.account_number].account_name)}</span
														>
													{/if}
												</div>
												<div class="flex items-center gap-2">
													<span class="text-xs text-stone-400">{formatNumber(e.amount)}</span>
													<button
														on:click={() => removeAccountDeposit(e.account_number)}
														class="text-red-400 hover:text-red-500 transition-colors"
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
							{#if Object.keys(dpByUnit || {}).length === 0}
								<div class="text-xs text-stone-500">No non-zero DP notes.</div>
							{/if}
						</div>
						<p class="text-xs text-stone-500 mt-1">
							Stored as mapping: account_number → amount (grouped by unit for display).
						</p>
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
								<svg class="w-5 h-5 text-red-400 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
									<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
								</svg>
								<div class="flex-1">
									<h4 class="text-sm font-medium text-red-400 mb-1">ลบข้อมูลบัญชีทั้งหมด</h4>
									<p class="text-xs text-red-400/80 mb-3">
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
				class="px-6 py-4 border-t border-stone-700 bg-stone-800/80 rounded-b-2xl flex items-center justify-end gap-3"
			>
				<button
					on:click={() => (showSettingsModal = false)}
					class="px-4 py-2 rounded-xl bg-stone-700 text-stone-300 hover:bg-stone-600 transition-colors"
				>
					Cancel
				</button>
				<button
					on:click={saveSettings}
					disabled={savingSettings}
					class="px-4 py-2 rounded-xl bg-indigo-500 text-white hover:bg-indigo-600 disabled:bg-stone-700 disabled:text-stone-500 disabled:cursor-not-allowed transition-colors"
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
		class="fixed inset-0 bg-black/60 backdrop-blur-sm z-60 flex items-center justify-center p-6"
		on:click={() => (showDeleteConfirmModal = false)}
		on:keydown={(e) => e.key === 'Escape' && (showDeleteConfirmModal = false)}
		role="dialog"
		aria-modal="true"
		aria-labelledby="delete-confirm-title"
		tabindex="-1"
	>
		<div
			class="bg-stone-800 border border-red-800/40 rounded-2xl shadow-xl w-full max-w-md mx-4"
			role="document"
			on:click|stopPropagation
			on:keydown|stopPropagation
			on:mousedown|stopPropagation
		>
			<div class="p-6">
				<div class="flex items-center mb-4">
					<div class="w-12 h-12 bg-red-500 rounded-2xl flex items-center justify-center mr-4 shadow-lg shadow-red-500/20">
						<svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
						</svg>
					</div>
					<div>
						<h3 id="delete-confirm-title" class="text-lg font-semibold text-stone-200">ยืนยันการลบข้อมูล</h3>
						<p class="text-sm text-stone-500">การดำเนินการนี้ไม่สามารถย้อนกลับได้</p>
					</div>
				</div>

				<div class="mb-6">
					<p class="text-sm text-stone-400 mb-3">
						คุณแน่ใจหรือไม่ที่จะลบข้อมูลบัญชีทั้งหมดจาก Supabase?
					</p>
					<div class="bg-red-50 border border-red-200 rounded-xl p-3">
						<p class="text-xs text-red-600">
							<strong>หมายเหตุ:</strong> การดำเนินการนี้จะลบเฉพาะข้อมูลบัญชีที่เข้ามาจาก EA เท่านั้น 
							การตั้งค่าอื่นๆ เช่น Initial Capital, Unit Mappings, WD Notes, DP Notes จะไม่ถูกลบ
						</p>
					</div>
				</div>

				<div class="flex items-center justify-end gap-3">
					<button
						on:click={() => (showDeleteConfirmModal = false)}
						class="px-4 py-2 rounded-xl bg-stone-700 text-stone-300 hover:bg-stone-600 transition-colors"
						disabled={deletingData}
					>
						ยกเลิก
					</button>
					<button
						on:click={clearAllAccountData}
						disabled={deletingData}
						class="px-4 py-2 rounded-xl bg-red-500 text-white hover:bg-red-600 disabled:bg-stone-700 disabled:text-stone-500 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
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
