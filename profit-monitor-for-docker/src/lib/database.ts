import Database from 'better-sqlite3';
import type { AccountData, AccountSummary, DashboardStats } from './types.js';
import { dev } from '$app/environment';

class SQLiteStorage {
	private db: Database.Database;

	constructor() {
		// Use different database files for dev and production
		const dbPath = dev ? 'data/profit-monitor-dev.db' : 'data/profit-monitor.db';
		
		// Create data directory if it doesn't exist
		this.ensureDataDirectory();

		this.db = new Database(dbPath);
		this.initDatabase();
	}

	private ensureDataDirectory(): void {
		try {
			// Use dynamic import for Node.js modules in ES modules
			import('fs').then(fs => {
				if (!fs.existsSync('data')) {
					fs.mkdirSync('data', { recursive: true });
				}
			}).catch(error => {
				console.warn('Could not create data directory:', error);
			});
		} catch (error) {
			console.warn('Could not create data directory:', error);
		}
	}

	private initDatabase(): void {
		// Create accounts table
		this.db.exec(`
			CREATE TABLE IF NOT EXISTS accounts (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				account_number TEXT NOT NULL,
				account_name TEXT NOT NULL,
				broker_name TEXT NOT NULL,
				balance REAL NOT NULL,
				equity REAL NOT NULL,
				unit INTEGER NOT NULL DEFAULT 1,
				timestamp TEXT NOT NULL,
				created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
				UNIQUE(account_number, timestamp)
			)
		`);

		// Create settings table
		this.db.exec(`
			CREATE TABLE IF NOT EXISTS settings (
				key TEXT PRIMARY KEY,
				value TEXT NOT NULL,
				updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
			)
		`);

		// Insert default initial capital if not exists
		const insertSetting = this.db.prepare(`
			INSERT OR IGNORE INTO settings (key, value) VALUES (?, ?)
		`);
		insertSetting.run('initial_capital', '60000');
		insertSetting.run('capital_per_unit', '7500');

		// Migration: Add unit column if it doesn't exist
		try {
			this.db.exec(`ALTER TABLE accounts ADD COLUMN unit INTEGER NOT NULL DEFAULT 1`);
		} catch (error) {
			// Column already exists, ignore error
		}

		// Create indexes for better performance
		this.db.exec(`
			CREATE INDEX IF NOT EXISTS idx_accounts_number ON accounts(account_number);
			CREATE INDEX IF NOT EXISTS idx_accounts_timestamp ON accounts(timestamp);
			CREATE INDEX IF NOT EXISTS idx_accounts_broker ON accounts(broker_name);
		`);
	}

	addAccountData(data: AccountData): void {
		const insert = this.db.prepare(`
			INSERT OR REPLACE INTO accounts 
			(account_number, account_name, broker_name, balance, equity, unit, timestamp)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		`);

		insert.run(
			data.account_number,
			data.account_name,
			data.broker_name,
			data.balance,
			data.equity,
			data.unit,
			data.timestamp
		);
	}

	getAllAccountData(): AccountData[] {
		const select = this.db.prepare(`
			SELECT account_number, account_name, broker_name, balance, equity, unit, timestamp
			FROM accounts
			ORDER BY timestamp DESC
		`);

		return select.all() as AccountData[];
	}

	getAccountSummaries(): AccountSummary[] {
		const select = this.db.prepare(`
			SELECT 
				account_number,
				account_name,
				broker_name,
				balance as latest_balance,
				equity as latest_equity,
				unit,
				timestamp as last_update
			FROM accounts a1
			WHERE timestamp = (
				SELECT MAX(timestamp)
				FROM accounts a2
				WHERE a2.account_number = a1.account_number
			)
			ORDER BY broker_name, account_number
		`);

		return select.all() as AccountSummary[];
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
		const update = this.db.prepare(`
			INSERT OR REPLACE INTO settings (key, value, updated_at)
			VALUES ('initial_capital', ?, CURRENT_TIMESTAMP)
		`);
		update.run(amount.toString());
	}

	getInitialCapital(): number {
		const select = this.db.prepare(`
			SELECT value FROM settings WHERE key = 'initial_capital'
		`);
		const result = select.get() as { value: string } | undefined;
		return result ? parseFloat(result.value) : 60000;
	}

	setCapitalPerUnit(amount: number): void {
		const update = this.db.prepare(`
			INSERT OR REPLACE INTO settings (key, value, updated_at)
			VALUES ('capital_per_unit', ?, CURRENT_TIMESTAMP)
		`);
		update.run(amount.toString());
	}

	getCapitalPerUnit(): number {
		const select = this.db.prepare(`
			SELECT value FROM settings WHERE key = 'capital_per_unit'
		`);
		const result = select.get() as { value: string } | undefined;
		return result ? parseFloat(result.value) : 7500;
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

	clearData(): void {
		this.db.exec('DELETE FROM accounts');
	}

	// Additional utility methods
	getAccountHistory(accountNumber: string, limit: number = 100): AccountData[] {
		const select = this.db.prepare(`
			SELECT account_number, account_name, broker_name, balance, equity, unit, timestamp
			FROM accounts
			WHERE account_number = ?
			ORDER BY timestamp DESC
			LIMIT ?
		`);

		return select.all(accountNumber, limit) as AccountData[];
	}

	getDataCount(): number {
		const select = this.db.prepare('SELECT COUNT(*) as count FROM accounts');
		const result = select.get() as { count: number };
		return result.count;
	}

	// Clean up old data (keep only last 1000 records per account)
	cleanupOldData(): void {
		const cleanup = this.db.prepare(`
			DELETE FROM accounts
			WHERE id NOT IN (
				SELECT id FROM (
					SELECT id,
						ROW_NUMBER() OVER (
							PARTITION BY account_number 
							ORDER BY timestamp DESC
						) as rn
					FROM accounts
				) ranked
				WHERE rn <= 1000
			)
		`);
		
		const result = cleanup.run();
		if (result.changes > 0) {
			console.log(`Cleaned up ${result.changes} old records`);
		}
	}

	// Close database connection
	close(): void {
		this.db.close();
	}
}

// Create singleton instance
export const storage = new SQLiteStorage();

// Cleanup old data on startup
storage.cleanupOldData();

// Export the class for testing
export { SQLiteStorage };
