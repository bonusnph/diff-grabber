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
			account_number VARCHAR(50) NOT NULL UNIQUE,
			account_name VARCHAR(255) NOT NULL,
			broker_name VARCHAR(255) NOT NULL,
			balance DECIMAL(15,2) NOT NULL,
			equity DECIMAL(15,2) NOT NULL,
			unit INTEGER NOT NULL DEFAULT 1,
			timestamp TIMESTAMPTZ NOT NULL,
			lastPositionSide VARCHAR(10) DEFAULT 'UNKNOWN',
			lastPositionEntryPrice DECIMAL(15,5) DEFAULT 0,
			created_at TIMESTAMPTZ DEFAULT NOW(),
			updated_at TIMESTAMPTZ DEFAULT NOW()
		);

		-- Create indexes
		CREATE INDEX IF NOT EXISTS idx_accounts_number ON accounts(account_number);
		CREATE INDEX IF NOT EXISTS idx_accounts_timestamp ON accounts(timestamp);
		CREATE INDEX IF NOT EXISTS idx_accounts_unit ON accounts(unit);

		-- Create trigger to update updated_at timestamp
		CREATE OR REPLACE FUNCTION update_updated_at_column()
		RETURNS TRIGGER AS $$
		BEGIN
			NEW.updated_at = NOW();
			RETURN NEW;
		END;
		$$ language 'plpgsql';

		CREATE TRIGGER update_accounts_updated_at BEFORE UPDATE ON accounts
		FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

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
				timestamp: data.timestamp,
				position_side: data.lastPositionSide ?? 'UNKNOWN',
				position_price: data.lastPositionEntryPrice ?? 0
			}, {
				onConflict: 'account_number'
			});

		if (error) {
			console.error('Error adding account data:', error);
			throw error;
		}
	}

	async getAllAccountData(): Promise<AccountData[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('account_number, account_name, broker_name, balance, equity, unit, timestamp, position_side, position_price')
			.order('timestamp', { ascending: false });

		if (error) {
			console.error('Error getting all account data:', error);
			throw error;
		}

		return (data || []).map(record => ({
			account_number: record.account_number,
			account_name: record.account_name,
			broker_name: record.broker_name,
			balance: record.balance,
			equity: record.equity,
			unit: record.unit,
			timestamp: record.timestamp,
			lastPositionSide: record.position_side ?? 'UNKNOWN',
			lastPositionEntryPrice: record.position_price ?? 0
		}));
	}

	async getAccountSummaries(): Promise<AccountSummary[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('account_number, account_name, broker_name, balance, equity, unit, timestamp, position_side, position_price')
			.order('timestamp', { ascending: false });

		if (error) {
			console.error('Error getting account summaries:', error);
			throw error;
		}

		// Transform data to match AccountSummary interface
		return (data || []).map(record => ({
			account_number: record.account_number,
			account_name: record.account_name,
			broker_name: record.broker_name,
			latest_balance: record.balance,
			latest_equity: record.equity,
			unit: record.unit,
			last_update: record.timestamp,
			lastPositionSide: record.position_side ?? 'UNKNOWN',
			lastPositionEntryPrice: record.position_price ?? 0
		}));
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

	// Deprecated: keep for backward compatibility (no-op)
	async setInitialCapital(amount: number): Promise<void> {
		// No-op: initial capital is now derived from unit_initial_capitals
	}

	async getInitialCapital(): Promise<number> {
		// Sum from unit_initial_capitals mapping; fallback to legacy initial_capital if not present
		const unitCaps = await this.getUnitInitialCapitals();
		const sum = Object.values(unitCaps || {}).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
		if (sum > 0) return sum;
		const { data } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'initial_capital')
			.single();
		return data ? parseFloat(data.setting_value) : 60000;
	}

	// Deprecated: per-unit capitals are used instead
	async setCapitalPerUnit(_amount: number): Promise<void> {}

	async getCapitalPerUnit(): Promise<number> { return 0; }

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
		const unitInitialCaps = await this.getUnitInitialCapitals();
		const accountWithdrawals = await this.getAccountWithdrawals();
		const accountDeposits = await this.getAccountDeposits();
		const stats: Array<{unit: number, totalBalance: number, profitLoss: number, accountCount: number}> = [];
		
		Object.entries(groupedAccounts).forEach(([unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			const totalBalance = accounts.reduce((sum, account) => sum + account.latest_balance, 0);
			const withdrawalAdjust = accounts.reduce((sum, acc) => sum + (accountWithdrawals[acc.account_number] ?? 0), 0);
			const depositAdjust = accounts.reduce((sum, acc) => sum + (accountDeposits[acc.account_number] ?? 0), 0);
			const unitCap = unitInitialCaps[unit] ?? 0;
			const profitLoss = totalBalance - unitCap + withdrawalAdjust - depositAdjust;
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

	async setUnitInitialCapitals(mappings: Record<number, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'unit_initial_capitals',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});
		if (error) {
			console.error('Error setting unit initial capitals:', error);
			throw error;
		}
	}

	async getUnitInitialCapitals(): Promise<Record<number, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'unit_initial_capitals')
			.single();
		if (error && error.code !== 'PGRST116') {
			console.error('Error getting unit initial capitals:', error);
			throw error;
		}
		if (data) {
			try { return JSON.parse(data.setting_value); } catch (_) {}
		}
		return {};
	}

	async setAccountWithdrawals(mappings: Record<string, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'account_withdrawals',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting account withdrawals:', error);
			throw error;
		}
	}

	async getAccountWithdrawals(): Promise<Record<string, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'account_withdrawals')
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error getting account withdrawals:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing account withdrawals:', parseError);
			}
		}

		return {};
	}

	async setAccountDeposits(mappings: Record<string, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'account_deposits',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting account deposits:', error);
			throw error;
		}
	}

	async getAccountDeposits(): Promise<Record<string, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'account_deposits')
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error getting account deposits:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing account deposits:', parseError);
			}
		}

		return {};
	}

	// Snapshot for total P/L (server-wide)
	async setSnapshotPL(payload: { value: number; kind: 'adjusted' | 'real'; timestamp?: string }): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'pl_snapshot',
				setting_value: JSON.stringify({ value: payload.value, kind: payload.kind, timestamp: payload.timestamp ?? new Date().toISOString() }),
				updated_at: new Date().toISOString()
			});
		if (error) {
			console.error('Error setting pl snapshot:', error);
			throw error;
		}
	}

	async clearSnapshotPL(): Promise<void> {
		console.log('Attempting to clear pl_snapshot from settings table...');
		
		// First, check if the record exists
		const { data: existingData, error: selectError } = await supabase
			.from('settings')
			.select('setting_key, setting_value')
			.eq('setting_key', 'pl_snapshot');
		
		console.log('Records found before clear:', existingData?.length || 0, existingData);
		
		if (selectError) {
			console.error('Error checking existing snapshot:', selectError);
		}
		
		// Use UPDATE with null instead of DELETE (to work around potential RLS issues)
		console.log('Using UPDATE method to set value to null...');
		const { data: updateData, error: updateError } = await supabase
			.from('settings')
			.update({ 
				setting_value: null,
				updated_at: new Date().toISOString()
			})
			.eq('setting_key', 'pl_snapshot')
			.select();
		
		if (updateError) {
			console.error('Error updating pl snapshot to null:', updateError);
			
			// If update fails, try delete as fallback
			console.log('Update failed, trying DELETE as fallback...');
			const { data: deleteData, error: deleteError } = await supabase
				.from('settings')
				.delete()
				.eq('setting_key', 'pl_snapshot')
				.select();
			
			console.log('Delete fallback result:', { deleteData, deleteError });
			
			if (deleteError && deleteError.code !== 'PGRST116') {
				throw deleteError;
			}
		} else {
			console.log('Update operation completed. Updated rows:', updateData?.length || 0);
			console.log('Updated data:', updateData);
		}
		
		// Verify clearing by trying to get the snapshot
		const verifyResult = await this.getSnapshotPL();
		if (verifyResult === null) {
			console.log('Snapshot successfully cleared - verification passed');
		} else {
			console.error('Snapshot still exists after clear operation:', verifyResult);
			
			// Last resort: try to overwrite with invalid data
			console.log('Trying last resort: overwrite with invalid data...');
			const { data: overwriteData, error: overwriteError } = await supabase
				.from('settings')
				.update({ 
					setting_value: '{}',
					updated_at: new Date().toISOString()
				})
				.eq('setting_key', 'pl_snapshot')
				.select();
			
			console.log('Overwrite result:', overwriteData, overwriteError);
		}
	}

	async getSnapshotPL(): Promise<{ value: number; kind: 'adjusted' | 'real'; timestamp: string } | null> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'pl_snapshot')
			.single();
				
		if (error && error.code !== 'PGRST116') {
			throw error;
		}
		if (!data || !data.setting_value || data.setting_value === 'null' || data.setting_value === '{}') {
			return null;
		}
		try {
			const obj = JSON.parse(data.setting_value);
			if (typeof obj?.value === 'number' && (obj?.kind === 'adjusted' || obj?.kind === 'real')) {
				const result = { value: obj.value, kind: obj.kind, timestamp: obj.timestamp ?? new Date().toISOString() };
				return result;
			}
		} catch (parseError) {
		}
		return null;
	}

	async setUnitWithdrawals(mappings: Record<number, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'unit_withdrawals',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting unit withdrawals:', error);
			throw error;
		}
	}

	async getUnitWithdrawals(): Promise<Record<number, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'unit_withdrawals')
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error getting unit withdrawals:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing unit withdrawals:', parseError);
			}
		}

		return {};
	}

	async getAccountHistory(accountNumber: string, limit: number = 100): Promise<AccountData[]> {
		const { data, error } = await supabase
			.from('accounts')
			.select('account_number, account_name, broker_name, balance, equity, unit, timestamp, position_side, position_price')
			.eq('account_number', accountNumber)
			.order('timestamp', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Error getting account history:', error);
			throw error;
		}

		return (data || []).map(record => ({
			account_number: record.account_number,
			account_name: record.account_name,
			broker_name: record.broker_name,
			balance: record.balance,
			equity: record.equity,
			unit: record.unit,
			timestamp: record.timestamp,
			lastPositionSide: record.position_side ?? 'UNKNOWN',
			lastPositionEntryPrice: record.position_price ?? 0
		}));
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
		console.log('Starting to clear all account data...');
		
		// First, check how many records exist
		const { count: beforeCount } = await supabase
			.from('accounts')
			.select('*', { count: 'exact', head: true });
		
		console.log(`Found ${beforeCount} records before deletion`);
		
		const { data, error } = await supabase
			.from('accounts')
			.delete()
			.not('id', 'is', null); // Delete all records

		if (error) {
			console.error('Error clearing data:', error);
			throw error;
		}
		
		// Check how many records remain
		const { count: afterCount } = await supabase
			.from('accounts')
			.select('*', { count: 'exact', head: true });
		
		console.log(`Records remaining after deletion: ${afterCount}`);
		console.log('Account data cleared successfully');
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

		return {};
	}

	// Unit-specific broker min margins: Record<unit, Record<broker_name, min_margin>>
	async setUnitBrokerMinMargins(mappings: Record<number, Record<string, number>>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'unit_broker_min_margins',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});

		if (error) {
			console.error('Error setting unit broker min margins:', error);
			throw error;
		}
	}

	async getUnitBrokerMinMargins(): Promise<Record<number, Record<string, number>>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'unit_broker_min_margins')
			.single();

		if (error && error.code !== 'PGRST116') {
			console.error('Error getting unit broker min margins:', error);
			throw error;
		}

		if (data) {
			try {
				return JSON.parse(data.setting_value);
			} catch (parseError) {
				console.error('Error parsing unit broker min margins:', parseError);
			}
		}

		return {};
	}


	// Deprecated: now per unit
	async setWarningEquityPercentage(_percentage: number): Promise<void> {}

	async getWarningEquityPercentage(): Promise<number> { return 0; }

	async setUnitWarningEquityPercentages(mappings: Record<number, number>): Promise<void> {
		const { error } = await supabase
			.from('settings')
			.upsert({
				setting_key: 'unit_warning_equity_percentages',
				setting_value: JSON.stringify(mappings),
				updated_at: new Date().toISOString()
			});
		if (error) {
			console.error('Error setting unit warning equity percentages:', error);
			throw error;
		}
	}

	async getUnitWarningEquityPercentages(): Promise<Record<number, number>> {
		const { data, error } = await supabase
			.from('settings')
			.select('setting_value')
			.eq('setting_key', 'unit_warning_equity_percentages')
			.single();
		if (error && error.code !== 'PGRST116') {
			console.error('Error getting unit warning equity percentages:', error);
			throw error;
		}
		if (data) {
			try { return JSON.parse(data.setting_value); } catch (_) {}
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
