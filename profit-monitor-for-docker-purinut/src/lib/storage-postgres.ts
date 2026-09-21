import dotenv from 'dotenv';
dotenv.config();
dotenv.config({ path: '.env.local', override: true });

import { existsSync, readFileSync } from 'node:fs';
import { Pool, type QueryResultRow } from 'pg';
import type {
	AccountData,
	AccountSummary,
	CurrencySettings,
	DashboardStats,
	EquityWarningState,
	PendingWithdrawal,
	PlAlertSettings,
	PlAlertState
} from './types.js';
import {
	defaultPlAlertSettings,
	defaultPlAlertState,
	normalizePlAlertSettings,
	normalizePlAlertState
} from './pl-alert-model.js';
import { normalizePendingWithdrawals } from './pending-withdrawal-model.js';
import { defaultEquityWarningState, normalizeEquityWarningState } from './equity-warning-model.js';
import { defaultCurrencySettings, normalizeCurrencySettings } from './currency.js';

const DEFAULT_UNIT_MAPPINGS = '{}';

function asNumber(value: unknown, fallback = 0): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value;
	if (typeof value === 'string' && value !== '') {
		const parsed = Number(value);
		if (Number.isFinite(parsed)) return parsed;
	}
	return fallback;
}

function asTimestamp(value: unknown): string {
	if (value instanceof Date) return value.toISOString();
	if (typeof value === 'string') return value;
	return new Date().toISOString();
}

function parseOrders(raw: unknown): AccountData['orders'] {
	if (!raw) return [];
	if (Array.isArray(raw)) return raw as AccountData['orders'];
	if (typeof raw === 'string') {
		try {
			const parsed = JSON.parse(raw);
			return Array.isArray(parsed) ? parsed : [];
		} catch {
			return [];
		}
	}
	return [];
}

function parseJson<T>(raw: string | null, fallback: T): T {
	if (!raw) return fallback;
	try {
		return JSON.parse(raw) as T;
	} catch (error) {
		console.error('Error parsing stored JSON:', error);
		return fallback;
	}
}

function mapAccountRow(record: QueryResultRow): AccountData {
	return {
		account_number: String(record.account_number),
		account_name: String(record.account_name),
		broker_name: String(record.broker_name),
		balance: asNumber(record.balance),
		equity: asNumber(record.equity),
		unit: asNumber(record.unit, 1),
		timestamp: asTimestamp(record.timestamp),
		lastPositionSide: record.position_side ?? 'UNKNOWN',
		lastPositionEntryPrice: asNumber(record.position_price),
		lastSize: asNumber(record.position_size),
		orders: parseOrders(record.position_orders)
	};
}

function mapAccountSummary(record: QueryResultRow): AccountSummary {
	const account = mapAccountRow(record);
	return {
		account_number: account.account_number,
		account_name: account.account_name,
		broker_name: account.broker_name,
		latest_balance: account.balance,
		latest_equity: account.equity,
		unit: account.unit,
		last_update: account.timestamp,
		lastPositionSide: account.lastPositionSide,
		lastPositionEntryPrice: account.lastPositionEntryPrice,
		lastSize: account.lastSize,
		orders: account.orders
	};
}

class PostgresStorage {
	private pool: Pool | null = null;
	private ready: Promise<void> | null = null;

	private getPool(): Pool {
		if (this.pool) return this.pool;

		const connectionString = process.env.DATABASE_URL;
		if (!connectionString) {
			throw new Error('DATABASE_URL is not set');
		}

		this.pool = new Pool({
			connectionString,
			max: 10
		});
		return this.pool;
	}

	private async ensureReady(): Promise<Pool> {
		const pool = this.getPool();
		if (!this.ready) {
			this.ready = this.initDatabase(pool).catch((error) => {
				this.ready = null;
				throw error;
			});
		}
		await this.ready;
		return pool;
	}

	private async initDatabase(pool: Pool): Promise<void> {
		await pool.query(`
			CREATE TABLE IF NOT EXISTS accounts (
				id SERIAL PRIMARY KEY,
				account_number VARCHAR(50) NOT NULL UNIQUE,
				account_name VARCHAR(255) NOT NULL,
				broker_name VARCHAR(255) NOT NULL,
				balance DECIMAL(15,2) NOT NULL,
				equity DECIMAL(15,2) NOT NULL,
				unit INTEGER NOT NULL DEFAULT 1,
				timestamp TIMESTAMPTZ NOT NULL,
				position_side VARCHAR(10) DEFAULT 'UNKNOWN',
				position_price DECIMAL(15,5) DEFAULT 0,
				position_size DECIMAL(15,2) DEFAULT 0,
				position_orders JSONB DEFAULT '[]'::jsonb,
				created_at TIMESTAMPTZ DEFAULT NOW(),
				updated_at TIMESTAMPTZ DEFAULT NOW()
			)
		`);

		await pool.query(`
			CREATE TABLE IF NOT EXISTS settings (
				setting_key VARCHAR(50) PRIMARY KEY,
				setting_value TEXT,
				updated_at TIMESTAMPTZ DEFAULT NOW()
			)
		`);

		await pool.query('CREATE INDEX IF NOT EXISTS idx_accounts_number ON accounts(account_number)');
		await pool.query('CREATE INDEX IF NOT EXISTS idx_accounts_timestamp ON accounts(timestamp)');
		await pool.query('CREATE INDEX IF NOT EXISTS idx_accounts_unit ON accounts(unit)');

		await pool.query(`
			CREATE OR REPLACE FUNCTION update_updated_at_column()
			RETURNS TRIGGER AS $$
			BEGIN
				NEW.updated_at = NOW();
				RETURN NEW;
			END;
			$$ language 'plpgsql'
		`);

		await pool.query(`DROP TRIGGER IF EXISTS update_accounts_updated_at ON accounts`);
		await pool.query(`
			CREATE TRIGGER update_accounts_updated_at
			BEFORE UPDATE ON accounts
			FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()
		`);

		await this.seedFromSupabaseDump(pool);

		await pool.query(
			`
			INSERT INTO settings (setting_key, setting_value) VALUES
				('initial_capital', '0'),
				('capital_per_unit', '0'),
				('total_active_accounts', '0'),
				('access_pin', '250514'),
				('unit_mappings', $1)
			ON CONFLICT (setting_key) DO NOTHING
			`,
			[DEFAULT_UNIT_MAPPINGS]
		);
	}

	private async seedFromSupabaseDump(pool: Pool): Promise<void> {
		const flag = await pool.query<{ setting_value: string | null }>(
			`SELECT setting_value FROM settings WHERE setting_key = 'migrated_from_supabase'`
		);
		if (flag.rows[0]?.setting_value) return;

		const settingsPath = process.env.SETTINGS_SEED_PATH || '/app/settings-seed.json';
		const accountsPath = process.env.ACCOUNTS_SEED_PATH || '/app/accounts-seed.json';
		let imported = false;

		if (existsSync(settingsPath)) {
			const rows = JSON.parse(readFileSync(settingsPath, 'utf8')) as Array<{
				setting_key?: string;
				setting_value?: string | null;
			}>;
			if (Array.isArray(rows)) {
				for (const row of rows) {
					if (!row?.setting_key) continue;
					await pool.query(
						`
						INSERT INTO settings (setting_key, setting_value, updated_at)
						VALUES ($1, $2, NOW())
						ON CONFLICT (setting_key)
						DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = NOW()
						`,
						[row.setting_key, row.setting_value ?? '']
					);
				}
				imported = true;
			}
		}

		if (existsSync(accountsPath)) {
			const rows = JSON.parse(readFileSync(accountsPath, 'utf8')) as Array<Record<string, unknown>>;
			if (Array.isArray(rows)) {
				for (const row of rows) {
					if (!row?.account_number) continue;
					await pool.query(
						`
						INSERT INTO accounts (
							account_number, account_name, broker_name, balance, equity, unit,
							timestamp, position_side, position_price, position_size, position_orders
						)
						VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
						ON CONFLICT (account_number) DO UPDATE SET
							account_name = EXCLUDED.account_name,
							broker_name = EXCLUDED.broker_name,
							balance = EXCLUDED.balance,
							equity = EXCLUDED.equity,
							unit = EXCLUDED.unit,
							timestamp = EXCLUDED.timestamp,
							position_side = EXCLUDED.position_side,
							position_price = EXCLUDED.position_price,
							position_size = EXCLUDED.position_size,
							position_orders = EXCLUDED.position_orders,
							updated_at = NOW()
						`,
						[
							String(row.account_number),
							String(row.account_name ?? ''),
							String(row.broker_name ?? ''),
							asNumber(row.balance),
							asNumber(row.equity),
							asNumber(row.unit, 1),
							asTimestamp(row.timestamp),
							row.position_side ?? 'UNKNOWN',
							asNumber(row.position_price),
							asNumber(row.position_size),
							JSON.stringify(row.position_orders ?? [])
						]
					);
				}
				imported = true;
			}
		}

		if (imported) {
			await pool.query(
				`
				INSERT INTO settings (setting_key, setting_value, updated_at)
				VALUES ('migrated_from_supabase', NOW()::text, NOW())
				ON CONFLICT (setting_key) DO NOTHING
				`
			);
		}
	}

	private async getSetting(key: string): Promise<string | null> {
		const pool = await this.ensureReady();
		const result = await pool.query<{ setting_value: string | null }>(
			'SELECT setting_value FROM settings WHERE setting_key = $1',
			[key]
		);
		return result.rows[0]?.setting_value ?? null;
	}

	private async setSetting(key: string, value: string): Promise<void> {
		const pool = await this.ensureReady();
		await pool.query(
			`
			INSERT INTO settings (setting_key, setting_value, updated_at)
			VALUES ($1, $2, NOW())
			ON CONFLICT (setting_key)
			DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = NOW()
			`,
			[key, value]
		);
	}

	async addAccountData(data: AccountData): Promise<void> {
		const pool = await this.ensureReady();
		await pool.query(
			`
			INSERT INTO accounts (
				account_number, account_name, broker_name, balance, equity, unit,
				timestamp, position_side, position_price, position_size, position_orders
			)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
			ON CONFLICT (account_number) DO UPDATE SET
				account_name = EXCLUDED.account_name,
				broker_name = EXCLUDED.broker_name,
				balance = EXCLUDED.balance,
				equity = EXCLUDED.equity,
				unit = EXCLUDED.unit,
				timestamp = EXCLUDED.timestamp,
				position_side = EXCLUDED.position_side,
				position_price = EXCLUDED.position_price,
				position_size = EXCLUDED.position_size,
				position_orders = EXCLUDED.position_orders,
				updated_at = NOW()
			`,
			[
				data.account_number,
				data.account_name,
				data.broker_name,
				data.balance,
				data.equity,
				data.unit,
				data.timestamp,
				data.lastPositionSide ?? 'UNKNOWN',
				data.lastPositionEntryPrice ?? 0,
				data.lastSize ?? 0,
				JSON.stringify(Array.isArray(data.orders) ? data.orders : [])
			]
		);
	}

	private async selectAccountRows(): Promise<QueryResultRow[]> {
		const pool = await this.ensureReady();
		const result = await pool.query(`
			SELECT
				account_number, account_name, broker_name, balance, equity, unit,
				timestamp, position_side, position_price, position_size, position_orders
			FROM accounts
			ORDER BY timestamp DESC
		`);
		return result.rows;
	}

	async getAllAccountData(): Promise<AccountData[]> {
		const rows = await this.selectAccountRows();
		return rows.map(mapAccountRow);
	}

	async getAccountSummaries(): Promise<AccountSummary[]> {
		const rows = await this.selectAccountRows();
		return rows.map(mapAccountSummary);
	}

	async getDashboardStats(): Promise<DashboardStats> {
		const summaries = await this.getAccountSummaries();
		const initialCapital = summaries.length === 0 ? 0 : await this.getInitialCapital();
		const totalBalance = summaries.reduce((sum, account) => sum + account.latest_balance, 0);

		return {
			total_balance: totalBalance,
			profit_loss: totalBalance - initialCapital,
			initial_capital: initialCapital,
			account_count: summaries.length
		};
	}

	async setInitialCapital(_amount: number): Promise<void> {}

	async getInitialCapital(): Promise<number> {
		const unitCaps = await this.getUnitInitialCapitals();
		return Object.values(unitCaps || {}).reduce((s, v) => s + (typeof v === 'number' ? v : 0), 0);
	}

	async setCapitalPerUnit(_amount: number): Promise<void> {}

	async getCapitalPerUnit(): Promise<number> {
		return 0;
	}

	async getAccountsByUnit(): Promise<Record<number, AccountSummary[]>> {
		const summaries = await this.getAccountSummaries();
		const grouped: Record<number, AccountSummary[]> = {};

		summaries.forEach((account) => {
			const unit = account.unit || 0;
			if (!grouped[unit]) grouped[unit] = [];
			grouped[unit].push(account);
		});

		return grouped;
	}

	async getUnitStats(): Promise<
		Array<{ unit: number; totalBalance: number; profitLoss: number; accountCount: number }>
	> {
		const groupedAccounts = await this.getAccountsByUnit();
		const unitInitialCaps = await this.getUnitInitialCapitals();
		const accountWithdrawals = await this.getAccountWithdrawals();
		const accountDeposits = await this.getAccountDeposits();
		const stats: Array<{
			unit: number;
			totalBalance: number;
			profitLoss: number;
			accountCount: number;
		}> = [];

		Object.entries(groupedAccounts).forEach(([unitStr, accounts]) => {
			const unit = parseInt(unitStr);
			const totalBalance = accounts.reduce((sum, account) => sum + account.latest_balance, 0);
			const withdrawalAdjust = accounts.reduce(
				(sum, acc) => sum + (accountWithdrawals[acc.account_number] ?? 0),
				0
			);
			const depositAdjust = accounts.reduce(
				(sum, acc) => sum + (accountDeposits[acc.account_number] ?? 0),
				0
			);
			const unitCap = unitInitialCaps[unit] ?? 0;

			stats.push({
				unit,
				totalBalance,
				profitLoss: totalBalance - unitCap + withdrawalAdjust - depositAdjust,
				accountCount: accounts.length
			});
		});

		return stats.sort((a, b) => a.unit - b.unit);
	}

	async setUnitInitialCapitals(mappings: Record<number, number>): Promise<void> {
		await this.setSetting('unit_initial_capitals', JSON.stringify(mappings));
	}

	async getUnitInitialCapitals(): Promise<Record<number, number>> {
		return parseJson(await this.getSetting('unit_initial_capitals'), {});
	}

	async setAccountWithdrawals(mappings: Record<string, number>): Promise<void> {
		await this.setSetting('account_withdrawals', JSON.stringify(mappings));
	}

	async getAccountWithdrawals(): Promise<Record<string, number>> {
		return parseJson(await this.getSetting('account_withdrawals'), {});
	}

	async setAccountDeposits(mappings: Record<string, number>): Promise<void> {
		await this.setSetting('account_deposits', JSON.stringify(mappings));
	}

	async getAccountDeposits(): Promise<Record<string, number>> {
		return parseJson(await this.getSetting('account_deposits'), {});
	}

	async setPendingWithdrawals(entries: PendingWithdrawal[]): Promise<void> {
		await this.setSetting('pending_withdrawals', JSON.stringify(normalizePendingWithdrawals(entries)));
	}

	async getPendingWithdrawals(): Promise<PendingWithdrawal[]> {
		return normalizePendingWithdrawals(parseJson(await this.getSetting('pending_withdrawals'), []));
	}

	async setSnapshotPL(payload: {
		value: number;
		kind: 'adjusted' | 'real';
		timestamp?: string;
	}): Promise<void> {
		await this.setSetting(
			'pl_snapshot',
			JSON.stringify({
				value: payload.value,
				kind: payload.kind,
				timestamp: payload.timestamp ?? new Date().toISOString()
			})
		);
	}

	async clearSnapshotPL(): Promise<void> {
		const pool = await this.ensureReady();
		await pool.query('DELETE FROM settings WHERE setting_key = $1', ['pl_snapshot']);
	}

	async getSnapshotPL(): Promise<{
		value: number;
		kind: 'adjusted' | 'real';
		timestamp: string;
	} | null> {
		const raw = await this.getSetting('pl_snapshot');
		if (!raw || raw === 'null' || raw === '{}') return null;
		try {
			const obj = JSON.parse(raw);
			if (typeof obj?.value === 'number' && (obj?.kind === 'adjusted' || obj?.kind === 'real')) {
				return {
					value: obj.value,
					kind: obj.kind,
					timestamp: obj.timestamp ?? new Date().toISOString()
				};
			}
		} catch {
			return null;
		}
		return null;
	}

	async setUnitWithdrawals(mappings: Record<number, number>): Promise<void> {
		await this.setSetting('unit_withdrawals', JSON.stringify(mappings));
	}

	async getUnitWithdrawals(): Promise<Record<number, number>> {
		return parseJson(await this.getSetting('unit_withdrawals'), {});
	}

	async getAccountHistory(accountNumber: string, limit: number = 100): Promise<AccountData[]> {
		const pool = await this.ensureReady();
		const result = await pool.query(
			`
			SELECT
				account_number, account_name, broker_name, balance, equity, unit,
				timestamp, position_side, position_price, position_size, position_orders
			FROM accounts
			WHERE account_number = $1
			ORDER BY timestamp DESC
			LIMIT $2
			`,
			[accountNumber, limit]
		);
		return result.rows.map(mapAccountRow);
	}

	async getDataCount(): Promise<number> {
		const pool = await this.ensureReady();
		const result = await pool.query<{ count: string }>('SELECT COUNT(*)::text AS count FROM accounts');
		return asNumber(result.rows[0]?.count);
	}

	async clearData(): Promise<void> {
		const pool = await this.ensureReady();
		await pool.query('DELETE FROM accounts');
	}

	async cleanupOldData(): Promise<void> {}

	async setTotalActiveAccounts(count: number): Promise<void> {
		await this.setSetting('total_active_accounts', count.toString());
	}

	async getTotalActiveAccounts(): Promise<number> {
		const value = await this.getSetting('total_active_accounts');
		return value ? parseInt(value) : 0;
	}

	async setUnitMappings(mappings: Record<number, string>): Promise<void> {
		await this.setSetting('unit_mappings', JSON.stringify(mappings));
	}

	async getUnitMappings(): Promise<Record<number, string>> {
		return parseJson(await this.getSetting('unit_mappings'), {});
	}

	async setUnitBrokerMinMargins(mappings: Record<number, Record<string, number>>): Promise<void> {
		await this.setSetting('unit_broker_min_margins', JSON.stringify(mappings));
	}

	async getUnitBrokerMinMargins(): Promise<Record<number, Record<string, number>>> {
		return parseJson(await this.getSetting('unit_broker_min_margins'), {});
	}

	async setWarningEquityPercentage(_percentage: number): Promise<void> {}

	async getWarningEquityPercentage(): Promise<number> {
		return 0;
	}

	async setUnitWarningEquityPercentages(mappings: Record<number, number>): Promise<void> {
		await this.setSetting('unit_warning_equity_percentages', JSON.stringify(mappings));
	}

	async getUnitWarningEquityPercentages(): Promise<Record<number, number>> {
		return parseJson(await this.getSetting('unit_warning_equity_percentages'), {});
	}

	getUnitName(unit: number): string {
		return `Unit ${unit}`;
	}

	async setPlAlertSettings(settings: PlAlertSettings): Promise<void> {
		await this.setSetting('pl_alert_settings', JSON.stringify(normalizePlAlertSettings(settings)));
	}

	async getPlAlertSettings(): Promise<PlAlertSettings> {
		return normalizePlAlertSettings(
			parseJson(await this.getSetting('pl_alert_settings'), defaultPlAlertSettings())
		);
	}

	async setPlAlertState(state: PlAlertState): Promise<void> {
		await this.setSetting('pl_alert_state', JSON.stringify(normalizePlAlertState(state)));
	}

	async getPlAlertState(): Promise<PlAlertState> {
		return normalizePlAlertState(
			parseJson(await this.getSetting('pl_alert_state'), defaultPlAlertState())
		);
	}

	async setEquityWarningState(state: EquityWarningState): Promise<void> {
		await this.setSetting('equity_warning_state', JSON.stringify(normalizeEquityWarningState(state)));
	}

	async getEquityWarningState(): Promise<EquityWarningState> {
		return normalizeEquityWarningState(
			parseJson(await this.getSetting('equity_warning_state'), defaultEquityWarningState())
		);
	}

	async setCurrencySettings(settings: CurrencySettings): Promise<void> {
		await this.setSetting('currency_settings', JSON.stringify(normalizeCurrencySettings(settings)));
	}

	async getCurrencySettings(): Promise<CurrencySettings> {
		return normalizeCurrencySettings(
			parseJson(await this.getSetting('currency_settings'), defaultCurrencySettings())
		);
	}

	async getAccessPin(): Promise<string> {
		return (await this.getSetting('access_pin')) || '250514';
	}
}

export const storage = new PostgresStorage();
