import type { AccountData, AccountSummary, DashboardStats } from './types.js';

class InMemoryStorage {
	private accountData: Map<string, AccountData> = new Map();
	private initialCapital: number = 60000;

	addAccountData(data: AccountData): void {
		// Add GMT+7 timestamp if not provided
		if (!data.timestamp) {
			const now = new Date();
			const gmt7 = new Date(now.getTime() + (7 * 60 * 60 * 1000));
			data.timestamp = gmt7.toISOString();
		}
		
		// Use account_number as key and overwrite existing data
		this.accountData.set(data.account_number, data);
	}

	getAllAccountData(): AccountData[] {
		return Array.from(this.accountData.values()).sort((a, b) => 
			new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
		);
	}

	getAccountSummaries(): AccountSummary[] {
		// Since we now store only latest data per account, convert directly
		const summaries = Array.from(this.accountData.values()).map(data => ({
			account_number: data.account_number,
			account_name: data.account_name,
			broker_name: data.broker_name,
			latest_balance: data.balance,
			latest_equity: data.equity,
			last_update: data.timestamp
		}));
		
		// Sort by broker_name, then by account_number
		return summaries.sort((a, b) => {
			if (a.broker_name !== b.broker_name) {
				return a.broker_name.localeCompare(b.broker_name);
			}
			return a.account_number.localeCompare(b.account_number);
		});
	}

	getDashboardStats(): DashboardStats {
		const summaries = this.getAccountSummaries();
		const totalBalance = summaries.reduce((sum, acc) => sum + acc.latest_balance, 0);
		const profitLoss = totalBalance - this.initialCapital;
		
		return {
			total_balance: totalBalance,
			profit_loss: profitLoss,
			initial_capital: this.initialCapital,
			account_count: summaries.length
		};
	}

	setInitialCapital(amount: number): void {
		this.initialCapital = amount;
	}

	getInitialCapital(): number {
		return this.initialCapital;
	}

	clearData(): void {
		this.accountData.clear();
	}
}

// Singleton instance
export const storage = new InMemoryStorage();
