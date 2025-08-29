import dotenv from 'dotenv';
dotenv.config()

import { createClient } from '@supabase/supabase-js';
import type { AccountData, AccountSummary, DashboardStats } from './types.js';

// Supabase client
const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseKey) {
	console.warn('Supabase credentials not found. Please set SUPABASE_URL and SUPABASE_ANON_KEY environment variables.');
}

const supabase = createClient(supabaseUrl, supabaseKey);

class SupabaseStorage {
	async initDatabase(): Promise<void> {
		// Tables will be created via Supabase Dashboard or SQL Editor
		// This is just for reference - run these in Supabase SQL Editor:
		
		/*
		-- Create accounts table
		CREATE TABLE IF NOT EXISTS accounts (
			id SERIAL PRIMARY KEY,
			account_number VARCHAR(50) NOT NULL,
			account_name VARCHAR(255) NOT NULL,
			broker_name VARCHAR(255) NOT NULL,
			balance DECIMAL(15,2) NOT NULL,
			equity DECIMAL(15,2) NOT NULL,
			unit INTEGER NOT NULL DEFAULT 1,
			timestamp TIMESTAMPTZ NOT NULL,
			created_at TIMESTAMPTZ DEFAULT NOW(),
			UNIQUE(account_number, timestamp)
		);

		-- Create indexes
		CREATE INDEX IF NOT EXISTS idx_accounts_number ON accounts(account_number);
		CREATE INDEX IF NOT EXISTS idx_accounts_timestamp ON accounts(timestamp);
		CREATE INDEX IF NOT EXISTS idx_accounts_unit ON accounts(unit);

		-- Create settings table
		CREATE TABLE IF NOT EXISTS settings (
			setting_key VARCHAR(50) PRIMARY KEY,
			setting_value TEXT NOT NULL,
			updated_at TIMESTAMPTZ DEFAULT NOW()
		);

		-- Insert default settings
		INSERT INTO settings (setting_key, setting_value) VALUES 
		('initial_capital', '60000'),
		('capital_per_unit', '7500'),
		('total_active_accounts', '16'),
		('access_pin', '250514'),
		('unit_mappings', '{"1":"neex-sell","2":"neex-buy","3":"neex-avg-sell","4":"neex-avg-buy","5":"xs-sell","6":"xs-buy","7":"xs-avg-sell","8":"xs-avg-buy"}')
		ON CONFLICT (setting_key) DO NOTHING;
		*/
	}

	async addAccountData(data: AccountData): Promise<void> {
		const { error } = await supabase
			.from('accounts')
			.upsert({
				account_number: data.account_number,
				account_name: data.account_name,
				broker_name: data.broker_name,
				balance: data.balance,
				equity: data.equity,
				unit: data.unit,
				timestamp: data.timestamp
			}, {
				onConflict: 'account_number,timestamp'
			});

		if (error) {
			console.error('Error adding account data:', error);
			throw error;
		}
	}

	async getAllAccountData(): Promise<AccountData[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('account_number, account_name, broker_name, balance, equity, unit, timestamp')
			.order('timestamp', { ascending: false });

		if (error) {
			console.error('Error getting all account data:', error);
			throw error;
		}

		return data || [];
	}

	async getAccountSummaries(): Promise<AccountSummary[]> {
		// Get latest record for each account using a window function
		const { data, error } = await supabase.rpc('get_account_summaries');

		if (error) {
			console.error('Error getting account summaries:', error);
			// Fallback to manual grouping if RPC function doesn't exist
			return this.getAccountSummariesFallback();
		}

		return data || [];
	}

	private async getAccountSummariesFallback(): Promise<AccountSummary[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('*')
			.order('timestamp', { ascending: false });

		if (error) throw error;

		// Group by account_number and get latest
		const latestByAccount = new Map<string, any>();
		
		data?.forEach(record => {
			if (!latestByAccount.has(record.account_number)) {
				latestByAccount.set(record.account_number, {
					account_number: record.account_number,
					account_name: record.account_name,
					broker_name: record.broker_name,
					latest_balance: record.balance,
					latest_equity: record.equity,
					unit: record.unit,
					last_update: record.timestamp
				});
			}
		});

		return Array.from(latestByAccount.values());
	}

	async getDashboardStats(): Promise<DashboardStats> {
		const summaries = await this.getAccountSummaries();
		const initialCapital = await this.getInitialCapital();
		
		const totalBalance = summaries.reduce((sum, account) => sum + account.latest_balance, 0);
		const profitLoss = totalBalance - initialCapital;
		
		return {
			total_balance: totalBalance,
			profit_loss: profitLoss,
			initial_capital: initialCapital,
			account_count: summaries.length
		};
	}

	async setInitialCapital(amount: number): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'initial_capital',
				setting_value: amount.toString(),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting initial capital:', error);
			throw error;
		}
	}

	async getInitialCapital(): Promise<number> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'initial_capital')
			.single();

		if (error || !data) {
			return 60000; // Default value
		}

		return parseFloat(data.setting_value);
	}

	async setCapitalPerUnit(amount: number): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'capital_per_unit',
				setting_value: amount.toString(),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting capital per unit:', error);
			throw error;
		}
	}

	async getCapitalPerUnit(): Promise<number> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'capital_per_unit')
			.single();

		if (error || !data) {
			return 7500; // Default value
		}

		return parseFloat(data.setting_value);
	}

	async getAccountsByUnit(): Promise<Record<number, AccountSummary[]>> {
		const summaries = await this.getAccountSummaries();
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

	async getUnitStats(): Promise<Array<{unit: number, totalBalance: number, profitLoss: number, accountCount: number}>> {
		const groupedAccounts = await this.getAccountsByUnit();
		const capitalPerUnit = await this.getCapitalPerUnit();
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

	async getAccountHistory(accountNumber: string, limit: number = 100): Promise<AccountData[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('account_number, account_name, broker_name, balance, equity, unit, timestamp')
			.eq('account_number', accountNumber)
			.order('timestamp', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Error getting account history:', error);
			throw error;
		}

		return data || [];
	}

	async getDataCount(): Promise<number> {
		const { count, error } = await supabase
			.from('accounts')
			.select('*', { count: 'exact', head: true });

		if (error) {
			console.error('Error getting data count:', error);
			return 0;
		}

		return count || 0;
	}

	async clearData(): Promise<void> {
		const { error } = await supabase
			.from('accounts')
			.delete()
			.neq('id', 0); // Delete all records

		if (error) {
			console.error('Error clearing data:', error);
			throw error;
		}
	}

	async cleanupOldData(): Promise<void> {
		// Keep only last 1000 records per account
		// This requires a more complex query - implement if needed
		console.log('Cleanup old data - implement if needed');
	}

	async setTotalActiveAccounts(count: number): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'total_active_accounts',
				setting_value: count.toString(),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting total active accounts:', error);
			throw error;
		}
	}

	async getTotalActiveAccounts(): Promise<number> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'total_active_accounts')
			.single();

		if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
			console.error('Error getting total active accounts:', error);
			throw error;
		}

		return data ? parseInt(data.setting_value) : 16;
	}

	async setUnitMappings(mappings: Record<number, string>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'unit_mappings',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting unit mappings:', error);
			throw error;
		}
	}

	async getUnitMappings(): Promise<Record<number, string>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'unit_mappings')
			.single();

		if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
			console.error('Error getting unit mappings:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing unit mappings:', parseError);
			}
		}

		return {
			1: 'neex-sell',
			2: 'neex-buy',
			3: 'neex-avg-sell',
			4: 'neex-avg-buy',
			5: 'xs-sell',
			6: 'xs-buy',
			7: 'xs-avg-sell',
			8: 'xs-avg-buy',
		};
	}

	async setBrokerMinMargins(mappings: Record<string, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'broker_min_margins',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting broker min margins:', error);
			throw error;
		}
	}

	async getBrokerMinMargins(): Promise<Record<string, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'broker_min_margins')
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error getting broker min margins:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing broker min margins:', parseError);
			}
		}

		return {};
	}

	getUnitName(unit: number): string {
		// This will need to be async in practice, but for compatibility
		// we'll implement it synchronously with a fallback
		return `Unit ${unit}`;
	}

	async getAccessPin(): Promise<string> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'access_pin')
			.single();

		if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
			console.error('Error getting access PIN:', error);
			throw error;
		}

		return data ? data.setting_value : '250514';
	}
}

// Create singleton instance
export const storage = new SupabaseStorage();
