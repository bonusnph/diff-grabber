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
	let initialCapital = 60000;
	let capitalPerUnit = 7500;
	let totalActiveAccounts = 16;
	let unitMappings: Record<number, string> = { 1: 'xs-sell', 2: 'xs-buy', 3: 'gold-sell' };
	let brokerMinMargins: Record<string, number> = {};
	let unitGroups: Record<string, AccountSummary[]> = {};
	let unitStats: Array<{unit: number, totalBalance: number, profitLoss: number, accountCount: number}> = [];
	let loading = true;
	let pollingInterval = 5; // seconds
	let intervalId: ReturnType<typeof setInterval> | null = null;
	let countdownSeconds = 0;
	let countdownInterval: ReturnType<typeof setInterval> | null = null;
	let autoFetchEnabled = false;
	let fetchedThisCycle = false;
	let lastCountdown = 0;
	let showSettingsModal = false;
	let savingSettings = false;
	let latestUpdate: number = 0;

	// PIN Protection
	let isAuthenticated = false;
	let showPinModal = true;
	let pinInput = '';
	let pinError = '';
	let correctPin = '759637';
	let pinLoading = false;

	// Unit mappings editing
	let newUnitNumber = '';
	let newUnitName = '';
	let newBrokerName = '';
	let newBrokerMargin: string = '';

	// Data completeness check
	$: currentActiveAccounts = summaries.length;
	$: isDataComplete = currentActiveAccounts >= totalActiveAccounts;
	$: dataCompletenessPercentage = totalActiveAccounts > 0 ? Math.round((currentActiveAccounts / totalActiveAccounts) * 100) : 0;

	// Group summaries by broker
	$: groupedSummaries = summaries.reduce((groups, summary) => {
		const broker = summary.broker_name;
		if (!groups[broker]) {
			groups[broker] = [];
		}
		groups[broker].push(summary);
		return groups;
	}, {} as Record<string, AccountSummary[]>);

	// Check if account is trading (balance != equity)
	function isTrading(account: AccountSummary): boolean {
		const balanceDiff = Math.abs(account.latest_balance - account.latest_equity);
		return balanceDiff > 0.01; // Consider difference > 0.01 as trading
	}

	// Count trading accounts and calculate trading pairs
	$: tradingAccountsCount = summaries.filter(isTrading).length;
	$: tradingPairs = Math.floor(tradingAccountsCount / 2);

	async function fetchData() {
		try {
			const response = await fetch(`/api/data?t=${Date.now()}`, {
				cache: 'no-store'
			});
			const data = await response.json();
			
			stats = data.stats;
			summaries = data.summaries;
			unitGroups = data.unitGroups || {};
			unitStats = data.unitStats || [];
			latestUpdate = (summaries || []).reduce((latest, a) => {
				const t = new Date(a.last_update).getTime();
				return t > latest ? t : latest;
			}, 0);
			loading = false;
		} catch (error) {
			console.error('Error fetching data:', error);
			loading = false;
		}
	}

	async function loadInitialCapital() {
		try {
			const response = await fetch('/api/settings');
			const data = await response.json();
			initialCapital = data.initial_capital;
			capitalPerUnit = data.capital_per_unit;
			totalActiveAccounts = data.total_active_accounts;
			unitMappings = data.unit_mappings || {};
			brokerMinMargins = data.broker_min_margins || {};
		} catch (error) {
			console.error('Error loading settings:', error);
			// Keep default values if loading fails
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
		countdownSeconds = (30 - (sec % 30)) % 30;
		// Detect new 30s cycle (count jumps up from 0 -> 29)
		const cycleStart = countdownSeconds > lastCountdown;
		if (cycleStart) {
			fetchedThisCycle = false;
		}
		// Trigger fetch one tick after 0 (i.e., when switching to 29)
		if (autoFetchEnabled && lastCountdown === 0 && countdownSeconds === 29 && !fetchedThisCycle) {
			fetchedThisCycle = true;
			fetchData();
		}
		lastCountdown = countdownSeconds;
	}

	function getDataAge(timestamp: string): { minutes: number; status: 'fresh' | 'warning' | 'danger' } {
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

	async function updateCapitalPerUnit() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ capital_per_unit: capitalPerUnit })
			});
			
			if (response.ok) {
				const data = await response.json();
				capitalPerUnit = data.capital_per_unit; // Update with confirmed value from server
				await fetchData(); // Refresh data to update unit stats
			}
		} catch (error) {
			console.error('Error updating capital per unit:', error);
			// Reload the original value if update fails
			await loadInitialCapital();
		}
	}

	async function updateTotalActiveAccounts() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ total_active_accounts: totalActiveAccounts })
			});
			
			if (response.ok) {
				const data = await response.json();
				totalActiveAccounts = data.total_active_accounts; // Update with confirmed value from server
			}
		} catch (error) {
			console.error('Error updating total active accounts:', error);
			// Reload the original value if update fails
			await loadInitialCapital();
		}
	}

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

	async function updateBrokerMinMargins() {
		try {
			const response = await fetch('/api/settings', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json'
				},
				body: JSON.stringify({ broker_min_margins: brokerMinMargins })
			});
			if (response.ok) {
				const data = await response.json();
				brokerMinMargins = data.broker_min_margins || brokerMinMargins;
			}
		} catch (error) {
			console.error('Error updating broker min margins:', error);
		}
	}

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

	function addBrokerMinMargin() {
		const name = newBrokerName.trim();
		const margin = parseFloat(newBrokerMargin);
		if (name && !isNaN(margin) && margin >= 0) {
			brokerMinMargins[name] = margin;
			updateBrokerMinMargins();
			newBrokerName = '';
			newBrokerMargin = '';
		}
	}

	function removeBrokerMinMargin(name: string) {
		delete brokerMinMargins[name];
		updateBrokerMinMargins();
	}

	function getUnitDisplayName(unit: number): string {
		return unitMappings[unit] || `Unit ${unit}`;
	}

	function getBrokerMinFor(name: string): number | undefined {
		if (!name) return undefined;
		const lower = name.toLowerCase();
		for (const [k, v] of Object.entries(brokerMinMargins || {})) {
			if (k.toLowerCase() === lower) return v as number;
		}
		return undefined;
	}

	function isInsufficientBalance(account: AccountSummary): boolean {
		const min = getBrokerMinFor(account.broker_name);
		if (min === undefined) return false;
		return account.latest_balance <= min;
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
			if (correctPin === '759637') {
				const response = await fetch('/api/settings');
				if (response.ok) {
					const settings = await response.json();
					// For now, use hardcoded PIN since we don't have PIN API endpoint yet
					correctPin = '759637';
				}
			}
			
			if (pinInput === correctPin) {
				isAuthenticated = true;
				showPinModal = false;
				pinInput = '';
				pinError = '';
				// Start loading data after authentication
				loadInitialCapital();
				fetchData();
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

	onMount(() => {
		// Don't load data until authenticated
		// Data loading will be triggered after PIN validation
		
		// Add keyboard event listener for PIN input
		document.addEventListener('keydown', handleKeydown);
		// Start 30s boundary countdown
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
					initial_capital: initialCapital,
					capital_per_unit: capitalPerUnit,
					total_active_accounts: totalActiveAccounts,
					unit_mappings: unitMappings
				})
			});
			if (response.ok) {
				const data = await response.json();
				initialCapital = data.initial_capital;
				capitalPerUnit = data.capital_per_unit;
				totalActiveAccounts = data.total_active_accounts;
				unitMappings = data.unit_mappings || unitMappings;
				await fetchData();
				showSettingsModal = false;
			}
		} catch (e) {
			console.error('Error saving settings:', e);
		} finally {
			savingSettings = false;
		}
	}
</script>

<svelte:head>
	<title>Profit Monitor Dashboard</title>
	<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover" />
</svelte:head>

<!-- PIN Protection Modal -->
{#if showPinModal}
	<div class="fixed inset-0 bg-black bg-opacity-90 flex items-center justify-center z-50">
		<div class="bg-gray-800 border border-gray-600 rounded-lg shadow-2xl p-8 w-full max-w-md mx-4">
			<div class="text-center mb-6">
				<div class="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center mx-auto mb-4">
					<svg class="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
					</svg>
				</div>
				<h2 class="text-2xl font-bold text-white mb-2">ป้อนรหัส PIN</h2>
				<p class="text-gray-400">กรุณาป้อนรหัส PIN เพื่อเข้าใช้งานระบบ</p>
			</div>

			<!-- PIN Display -->
			<div class="flex justify-center space-x-2 mb-6">
				{#each Array(6) as _, i}
					<div class="w-12 h-12 border-2 border-gray-600 rounded-lg flex items-center justify-center bg-gray-700">
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
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
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
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2M3 12l6.414 6.414a2 2 0 001.414.586H19a2 2 0 002-2V7a2 2 0 00-2-2h-8.172a2 2 0 00-1.414.586L3 12z" />
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
						<circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
						<path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
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

<div class="min-h-screen bg-gray-900 p-6" class:hidden={showPinModal}>
	<div class="max-w-7xl mx-auto">
		<!-- Header -->
		<div class="mb-8">
			<div class="flex flex-col md:flex-row md:justify-between md:items-center mb-4 gap-3">
				<div>
					<h1 class="text-3xl font-bold text-white mb-2">Profit Monitor Dashboard</h1>
					<div class="flex flex-col sm:flex-row sm:items-center gap-1 sm:gap-3">
						<p class="text-gray-300">Real-time trading account monitoring</p>
						<div class="flex items-center gap-1 text-sm text-gray-400">
							<div class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
							<span>Live</span>
						</div>
					</div>
				</div>
				<div class="flex items-center gap-2 mt-1 md:mt-0 flex-wrap">
					<button
						on:click={fetchData}
						class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-md text-sm font-medium transition-colors flex items-center space-x-2"
						disabled={loading}
					>
						<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
						</svg>
						<span>{loading ? 'Loading...' : 'Refresh'}</span>
					</button>
					<button
						on:click={() => showSettingsModal = true}
						class="bg-gray-700 hover:bg-gray-600 text-gray-300 hover:text-white p-2 rounded-md transition-colors"
						title="Settings"
						aria-label="Open Settings"
					>
						<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
						</svg>
					</button>
				</div>
			</div>
		</div>

		{#if loading}
			<div class="flex justify-center items-center h-64">
				<div class="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-400"></div>
			</div>
		{:else}
			<!-- Profit/Loss Highlight Card -->
			<div class="bg-gradient-to-r from-gray-800 to-gray-700 border border-gray-600 rounded-xl shadow-2xl p-8 mb-8 text-white">
				<div class="flex flex-col gap-1 md:flex-row md:items-center md:justify-between mb-4">
					<h2 class="text-lg font-medium text-gray-300 uppercase tracking-wide">Total Profit/Loss</h2>
					<div class="flex flex-col text-xs text-gray-400 md:flex-row md:items-center md:gap-3">
						{#if latestUpdate}
							<span>Updated: {formatDateTime(new Date(latestUpdate).toISOString())}</span>
						{/if}
						<span>Next refresh in: {String(countdownSeconds).padStart(2,'0')}s</span>
					</div>
				</div>
				<div class="text-center">
					<p class="text-5xl font-bold mb-2 {!isDataComplete ? 'opacity-60' : ''}" class:text-green-400={stats.profit_loss >= 0} class:text-red-400={stats.profit_loss < 0}>
						{stats.profit_loss >= 0 ? '+' : ''}{formatNumber(stats.profit_loss)}
					</p>
					<div class="mt-2 flex items-center justify-center gap-2">
						<span class="px-2 py-0.5 rounded-full text-xs font-medium"
							class:bg-green-700={stats.profit_loss >= 0}
							class:bg-red-700={stats.profit_loss < 0}
						>
							{stats.profit_loss >= 0 ? 'Profitable' : 'Loss'}
						</span>
						{#if !isDataComplete}
							<span class="px-2 py-0.5 rounded-full text-xs font-medium bg-yellow-900 border border-yellow-600 text-yellow-200">Partial Data</span>
						{/if}
					</div>
				</div>
			</div>

			<!-- Summary Cards -->
			<div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
				<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-6">
					<h3 class="text-sm font-medium text-gray-400 uppercase tracking-wide">Trading Pairs</h3>
					<p class="text-2xl font-bold text-blue-400 mt-2">
						{tradingPairs}
					</p>
					<p class="text-xs text-gray-500 mt-1">
						{tradingAccountsCount} accounts trading
					</p>
				</div>
				
				<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-6">
					<h3 class="text-sm font-medium text-gray-400 uppercase tracking-wide">Active Accounts</h3>
					<p class="text-2xl font-bold text-white mt-2">
						{stats.account_count}
					</p>
				</div>
			</div>

			<!-- Account Summaries by Unit -->
			<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-6 mb-8">
				<h2 class="text-xl font-semibold text-white mb-6">Account Summary by Unit</h2>
				
				{#each Object.entries(unitGroups) as [unitStr, accounts]}
					{@const unit = parseInt(unitStr)}
					{@const unitStat = unitStats.find(s => s.unit === unit)}
					{@const groupIsTrading = accounts.some(isTrading)}
					<div class="mb-6 rounded-md"
						class:bg-blue-700={groupIsTrading}
						class:border-2={groupIsTrading}
						class:border-blue-400={groupIsTrading}
						class:p-2={groupIsTrading}
					>
						<div class="flex justify-between items-center mb-3 border-b border-gray-600 pb-2">
							<div class="flex items-center space-x-2">
								<h3 class="text-lg font-medium text-gray-200">
									{unit === 0 ? 'Unknown Unit' : getUnitDisplayName(unit)}
								</h3>
								<span class="text-xs text-gray-500 bg-gray-600 px-2 py-1 rounded">
									#{unit}
								</span>
							</div>
							{#if unitStat}
								<div class="flex flex-col md:flex-row items-start md:items-center space-y-1 md:space-y-0 md:space-x-4 text-sm">
									<span class="text-gray-400">
										Total: {formatNumber(unitStat.totalBalance)}
									</span>
									<span class="font-medium" class:text-green-400={unitStat.profitLoss >= 0} class:text-red-400={unitStat.profitLoss < 0}>
										P/L: {unitStat.profitLoss >= 0 ? '+' : ''}{formatNumber(unitStat.profitLoss)}
									</span>
								</div>
							{/if}
						</div>
						<!-- Compact Table View -->
						<div class="overflow-x-auto">
							<table class="w-full text-sm">
								<thead>
									<tr class="border-b border-gray-600">
										<th class="text-left py-2 px-3 text-gray-400 font-medium">Account / Name</th>
										<th class="text-right py-2 px-3 text-gray-400 font-medium">Balance</th>
										<th class="text-right py-2 px-3 text-gray-400 font-medium">Equity</th>
										<th class="text-left py-2 px-3 text-gray-400 font-medium">Broker</th>
										<th class="text-right py-2 px-3 text-gray-400 font-medium">Adjust</th>
										<th class="text-left py-2 px-3 text-gray-400 font-medium">Updated</th>
									</tr>
								</thead>
								<tbody>
									{#each accounts as account}
										{@const dataAge = getDataAge(account.last_update)}
										<tr class="border-b border-gray-700 hover:bg-gray-600 transition-colors"
											class:bg-yellow-900={dataAge.status === 'warning'}
											class:bg-red-900={dataAge.status === 'danger'}
											class:bg-red-950={isInsufficientBalance(account)}
										>
											<td class="py-2 px-3">
												<div class="flex flex-col leading-tight">
													<span class="font-mono font-semibold text-white">
														{#if isInsufficientBalance(account)}<span class="text-red-400">*</span> {/if}{account.account_number}
													</span>
													<span class="text-gray-400 text-xs truncate" title={account.account_name}>{shortName(account.account_name)}</span>
												</div>
											</td>
											<td class="py-2 px-3 text-right font-medium text-white">{formatNumber(account.latest_balance)}</td>
											<td class="py-2 px-3 text-right font-medium text-white">{formatNumber(account.latest_equity)}</td>
											<td class="py-2 px-3 text-gray-400 text-xs">{account.broker_name}</td>
											<td class="py-2 px-3 text-right font-medium"
												class:text-green-400={(capitalPerUnit / 2) - account.latest_balance >= 0}
												class:text-red-400={(capitalPerUnit / 2) - account.latest_balance < 0}
											>
												{((capitalPerUnit / 2) - account.latest_balance) >= 0 ? '+' : ''}{formatNumber((capitalPerUnit / 2) - account.latest_balance)}
											</td>
											<td class="py-2 px-3 text-gray-400 text-xs">{formatDateTime(account.last_update)}</td>
										</tr>
									{/each}
								</tbody>
							</table>
						</div>
					</div>
				{/each}
			</div>

			{#if summaries.length === 0}
				<div class="bg-gray-800 border border-gray-700 rounded-lg shadow-lg p-8">
					<div class="text-center text-gray-400">
						<svg class="mx-auto h-12 w-12 text-gray-500 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
							<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
						</svg>
						<h3 class="text-lg font-medium text-white mb-2">No Data Available</h3>
						<p class="text-gray-300">Waiting for EA to send account data...</p>
						<p class="text-sm text-gray-500 mt-2">Make sure your EA is running and configured with the correct API URL.</p>
					</div>
				</div>
			{/if}
		{/if}
	</div>
</div>

<!-- Settings Modal -->
{#if showSettingsModal}
	<div class="fixed inset-0 bg-black bg-opacity-70 z-50 overflow-y-auto flex items-center justify-center p-6" 
		 on:click={() => showSettingsModal = false}
		 on:keydown={(e) => e.key === 'Escape' && (showSettingsModal = false)}
		 role="dialog"
		 aria-modal="true"
		 aria-labelledby="settings-title"
		 tabindex="-1">
		<div class="bg-gray-800 border border-gray-600 rounded-lg shadow-2xl w-full max-w-md mx-4 my-8 flex flex-col max-h-[85vh]" 
			 role="document"
			 on:click|stopPropagation
			 on:mousedown|stopPropagation>
			<div class="flex justify-between items-center p-6 pb-4">
				<h2 id="settings-title" class="text-xl font-semibold text-white">Settings</h2>
				<button
					on:click={() => showSettingsModal = false}
					class="text-gray-400 hover:text-gray-200 transition-colors"
					aria-label="Close Settings"
				>
					<svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
						<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
					</svg>
				</button>
			</div>
			<div class="flex-1 overflow-y-auto px-6 pb-4 space-y-6">
				<!-- Initial Capital Setting -->
				<div>
					<label for="modal-initial-capital" class="block text-sm font-medium text-gray-300 mb-2">
						Initial Capital
					</label>
					<div class="flex items-center space-x-3">
						<input
							id="modal-initial-capital"
							type="number"
							bind:value={initialCapital}
							on:change={updateInitialCapital}
							class="flex-1 border border-gray-600 bg-gray-700 text-white rounded-md px-3 py-2 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							step="1000"
							min="0"
						/>
						<span class="text-sm text-gray-400">THB</span>
					</div>
					<p class="text-xs text-gray-500 mt-1">
						This value is used to calculate profit/loss
					</p>
				</div>

				<!-- Capital Per Unit Setting -->
				<div>
					<label for="modal-capital-per-unit" class="block text-sm font-medium text-gray-300 mb-2">
						Capital Per Unit
					</label>
					<div class="flex items-center space-x-3">
						<input
							id="modal-capital-per-unit"
							type="number"
							bind:value={capitalPerUnit}
							on:change={updateCapitalPerUnit}
							class="flex-1 border border-gray-600 bg-gray-700 text-white rounded-md px-3 py-2 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
							step="100"
							min="0"
						/>
						<span class="text-sm text-gray-400">THB</span>
					</div>
					<p class="text-xs text-gray-500 mt-1">
						Capital amount per unit for P/L calculation
					</p>
				</div>

				<!-- Total Active Accounts Setting -->
				<div>
					<label for="totalActiveAccounts" class="block text-sm font-medium text-gray-300 mb-2">Total Active Accounts</label>
					<input
						id="totalActiveAccounts"
						type="number"
						bind:value={totalActiveAccounts}
						min="1"
						class="w-full border border-gray-600 bg-gray-700 text-white rounded-md px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
					/>
					<p class="text-xs text-gray-500 mt-1">
						Expected number of active EA accounts for complete data
					</p>
				</div>

							<!-- Unit Mappings Setting -->
			<div>
				<fieldset>
					<legend class="block text-sm font-medium text-gray-300 mb-2">
						Unit Mappings
					</legend>
					
					<!-- Existing mappings -->
					<div class="space-y-2 mb-3">
						{#each Object.entries(unitMappings) as [unit, name]}
							<div class="flex items-center justify-between bg-gray-700 border border-gray-600 rounded-md px-3 py-2">
								<div class="flex items-center space-x-2">
									<span class="text-sm font-medium text-gray-300">Unit {unit}:</span>
									<span class="text-sm text-white">{name}</span>
								</div>
								<button
									on:click={() => removeUnitMapping(parseInt(unit))}
									class="text-red-400 hover:text-red-300 transition-colors"
									aria-label={`Remove mapping for unit ${unit}`}
								>
									<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
										<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
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

			<!-- Broker Min Margin Settings -->
			<div>
				<fieldset>
					<legend class="block text-sm font-medium text-gray-300 mb-2">
						Broker Min Margin
					</legend>
					<div class="space-y-2 mb-3">
						{#each Object.entries(brokerMinMargins) as [broker, margin]}
							<div class="flex items-center justify-between bg-gray-700 border border-gray-600 rounded-md px-3 py-2">
								<div class="flex items-center space-x-2">
									<span class="text-sm font-medium text-gray-300">{broker}</span>
									<span class="text-sm text-white">= {formatNumber(margin)}</span>
								</div>
								<button
									on:click={() => removeBrokerMinMargin(broker)}
									class="text-red-400 hover:text-red-300 transition-colors"
									aria-label={`Remove min margin for broker ${broker}`}
								>
									<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
										<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
									</svg>
								</button>
							</div>
						{/each}
					</div>
					<div class="flex items-center space-x-2">
						<input
							type="text"
							bind:value={newBrokerName}
							placeholder="Broker name"
							class="flex-1 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
						/>
						<span class="text-gray-400">=</span>
						<input
							type="number"
							bind:value={newBrokerMargin}
							placeholder="Min margin"
							min="0"
							class="w-32 border border-gray-600 bg-gray-700 text-white rounded-md px-2 py-1 text-right focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
						/>
						<button
							on:click={addBrokerMinMargin}
							class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded-md text-sm transition-colors"
							disabled={!newBrokerName.trim() || !newBrokerMargin}
						>
							Add
						</button>
					</div>
					<p class="text-xs text-gray-500 mt-1">
						Map broker (case-insensitive) to minimum margin. Used to flag low balance rows.
					</p>
				</fieldset>
			</div>

				<!-- Auto Refresh Info removed per new 30s countdown policy -->
			</div>

			<div class="px-6 py-4 border-t border-gray-700 bg-gray-800 flex items-center justify-end gap-3">
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