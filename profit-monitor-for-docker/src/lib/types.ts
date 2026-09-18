export interface OrderInfo {
	symbol: string;
	side: 'BUY' | 'SELL';
	price: number;
	lots: number;
	openTime: string;
	/** Same magic on BUY and SELL legs identifies one hedge pair across accounts. */
	magic?: number;
}

export interface AccountData {
	account_number: string;
	account_name: string;
	broker_name: string;
	balance: number;
	equity: number;
	unit: number;
	timestamp: string;
	lastPositionSide?: 'BUY' | 'SELL' | 'UNKNOWN';
	lastPositionEntryPrice?: number;
	lastSize?: number;
	orders?: OrderInfo[];
}

export interface AccountSummary {
	account_number: string;
	account_name: string;
	broker_name: string;
	latest_balance: number;
	latest_equity: number;
	unit: number;
	last_update: string;
	lastPositionSide?: 'BUY' | 'SELL' | 'UNKNOWN';
	lastPositionEntryPrice?: number;
	lastSize?: number;
	orders?: OrderInfo[];
}

export interface DashboardStats {
	total_balance: number;
	profit_loss: number;
	initial_capital: number;
	account_count: number;
}

export interface PlAlertSettings {
	profitEnabled: boolean;
	profitThreshold: number;
	lossEnabled: boolean;
	lossThreshold: number;
	recipientEmail: string;
}

export interface PlAlertState {
	profitPaused: boolean;
	lossPaused: boolean;
	lastProfitSentAt: string | null;
	lastLossSentAt: string | null;
}

export type DisplayCurrency = 'USD' | 'THB';
export type FxRateMode = 'live' | 'fixed';
export type FxDisplayMode = 'live' | 'live+buffer' | 'fixed';

export interface CurrencySettings {
	currency: DisplayCurrency;
	rateMode: FxRateMode;
	fixedRate: number;
	liveBuffer: number;
}

export interface FxQuote {
	currency: DisplayCurrency;
	rate: number;
	rawRate: number;
	buffer: number;
	mode: FxRateMode;
	displayMode: FxDisplayMode;
	source: string;
	fetchedAt: string;
}
