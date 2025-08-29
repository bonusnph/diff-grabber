import type { AccountData, AccountSummary, DashboardStats } from './types.js';

class MemoryStorage {
	private accounts: Map<string, AccountData[]> = new Map();
	private settings: Map<string, string> = new Map();

	constructor() {
		// Initialize default settings
		this.settings.set('initial_capital', '60000');
		this.settings.set('capital_per_unit', '7500');
		this.settings.set('total_active_accounts', '16');
		this.settings.set('unit_mappings', JSON.stringify({
			1: 'neex-sell',
			2: 'neex-buy',
			3: 'neex-avg-sell',
			4: 'neex-avg-buy',
			5: 'xs-sell',
			6: 'xs-buy',
			7: 'xs-avg-sell',
			8: 'xs-avg-buy',
		}));
	}

	addAccountData(data: AccountData): void {
		const key = data.account_number;
		if (!this.accounts.has(key)) {
			this.accounts.set(key, []);
		}
		
		const accountHistory = this.accounts.get(key)!;
		
		// Remove existing entry with same timestamp to avoid duplicates
		const existingIndex = accountHistory.findIndex(entry => entry.timestamp === data.timestamp);
		if (existingIndex !== -1) {
			accountHistory[existingIndex] = data;
		} else {
			accountHistory.push(data);
		}
		
		// Keep only last 1000 entries per account
		if (accountHistory.length > 1000) {
			accountHistory.splice(0, accountHistory.length - 1000);
		}
		
		// Sort by timestamp
		accountHistory.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
	}

	getAllAccountData(): AccountData[] {
		const allData: AccountData[] = [];
		for (const accountHistory of this.accounts.values()) {
			allData.push(...accountHistory);
		}
		return allData.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());
	}

	getAccountSummaries(): AccountSummary[] {
		const summaries: AccountSummary[] = [];
		
		for (const [accountNumber, accountHistory] of this.accounts.entries()) {
			if (accountHistory.length === 0) continue;
			
			// Get latest entry for each account
			const latest = accountHistory[0]; // Already sorted by timestamp desc
			
			summaries.push({
				account_number: latest.account_number,
				account_name: latest.account_name,
				broker_name: latest.broker_name,
				latest_balance: latest.balance,
				latest_equity: latest.equity,
				unit: latest.unit,
				last_update: latest.timestamp
			});
		}
		
		return summaries.sort((a, b) => {
			// Sort by broker_name, then account_number
			if (a.broker_name !== b.broker_name) {
				return a.broker_name.localeCompare(b.broker_name);
			}
			return a.account_number.localeCompare(b.account_number);
		});
	}

	getDashboardStats(): DashboardStats {
		const summaries = this.getAccountSummaries();
		const initialCapital = this.getInitialCapital();
		
		const totalBalance = summaries.reduce((sum, account) => sum + account.latest_balance, 0);
		const profitLoss = totalBalance - initialCapital;
		
		return {
			total_balance: totalBalance,
			profit_loss: profitLoss,
			initial_capital: initialCapital,
			account_count: summaries.length
		};
	}

	setInitialCapital(amount: number): void {
		this.settings.set('initial_capital', amount.toString());
	}

	getInitialCapital(): number {
		const value = this.settings.get('initial_capital');
		return value ? parseFloat(value) : 60000;
	}

	setCapitalPerUnit(amount: number): void {
		this.settings.set('capital_per_unit', amount.toString());
	}

	getCapitalPerUnit(): number {
		const value = this.settings.get('capital_per_unit');
		return value ? parseFloat(value) : 7500;
	}

	setTotalActiveAccounts(count: number): void {
		this.settings.set('total_active_accounts', count.toString());
	}

	getTotalActiveAccounts(): number {
		const value = this.settings.get('total_active_accounts');
		return value ? parseInt(value) : 16;
	}

	setUnitMappings(mappings: Record<number, string>): void {
		this.settings.set('unit_mappings', JSON.stringify(mappings));
	}

	getUnitMappings(): Record<number, string> {
		const value = this.settings.get('unit_mappings');
		if (value) {
			try {
				return JSON.parse(value);
			} catch (error) {
				console.error('Error parsing unit mappings:', error);
			}
		}
		return {
			1: 'xs-sell',
			2: 'xs-buy',
			3: 'gold-sell'
		};
	}

	addUnitMapping(unit: number, name: string): void {
		const mappings = this.getUnitMappings();
		mappings[unit] = name;
		this.setUnitMappings(mappings);
	}

	removeUnitMapping(unit: number): void {
		const mappings = this.getUnitMappings();
		delete mappings[unit];
		this.setUnitMappings(mappings);
	}

	getUnitName(unit: number): string {
		const mappings = this.getUnitMappings();
		return mappings[unit] || `Unit ${unit}`;
	}

	getAccountsByUnit(): Record<number, AccountSummary[]> {
		const summaries = this.getAccountSummaries();
		const grouped: Record<number, AccountSummary[]> = {};
		
		summaries.forEach(account => {
			const unit = account.unit || 0;
			if (!grouped[unit]) {
				grouped[unit] = [];
			}
			grouped[unit].push(account);
		});
		
		return grouped;
	}

	getUnitStats(): Array<{unit: number, totalBalance: number, profitLoss: number, accountCount: number}> {
		const groupedAccounts = this.getAccountsByUnit();
		const capitalPerUnit = this.getCapitalPerUnit();
		const stats: Array<{unit: number, totalBalance: number, profitLoss: number, accountCount: number}> = [];
		
		Object.entries(groupedAccounts).forEach(([unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			const totalBalance = accounts.reduce((sum, account) => sum + account.latest_balance, 0);
			const profitLoss = totalBalance - capitalPerUnit;
			const accountCount = accounts.length;
			
			stats.push({
				unit,
				totalBalance,
				profitLoss,
				accountCount
			});
		});
		
		return stats.sort((a, b) => a.unit - b.unit);
	}

	getAccountHistory(accountNumber: string, limit: number = 100): AccountData[] {
		const accountHistory = this.accounts.get(accountNumber);
		if (!accountHistory) return [];
		
		return accountHistory.slice(0, limit);
	}

	getDataCount(): number {
		let count = 0;
		for (const accountHistory of this.accounts.values()) {
			count += accountHistory.length;
		}
		return count;
	}

	clearData(): void {
		this.accounts.clear();
	}

	// Clean up old data (keep only last 1000 records per account)
	cleanupOldData(): void {
		for (const [accountNumber, accountHistory] of this.accounts.entries()) {
			if (accountHistory.length > 1000) {
				accountHistory.splice(0, accountHistory.length - 1000);
			}
		}
	}

	// Close database connection (no-op for memory storage)
	close(): void {
		// Nothing to close for in-memory storage
	}
}

// Create singleton instance
export const storage = new MemoryStorage();
