import type { PendingWithdrawal } from './types.js';

export const PENDING_NOTE_MAX_LENGTH = 200;

export function normalizePendingNote(raw: unknown): string {
	if (typeof raw !== 'string') return '';
	return raw.trim().slice(0, PENDING_NOTE_MAX_LENGTH);
}

export function parsePendingAmount(raw: unknown): number | null {
	const amount =
		typeof raw === 'number' ? raw : typeof raw === 'string' && raw !== '' ? Number(raw) : NaN;
	if (!Number.isFinite(amount) || amount <= 0) return null;
	return Math.round(amount * 100) / 100;
}

export function parsePendingTimestamp(raw: unknown, fallback: string): string {
	if (typeof raw === 'string' && raw.trim()) {
		const parsed = new Date(raw);
		if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
	}
	return fallback;
}

export function normalizePendingWithdrawal(raw: unknown): PendingWithdrawal | null {
	if (!raw || typeof raw !== 'object') return null;
	const value = raw as Record<string, unknown>;
	const id = typeof value.id === 'string' ? value.id.trim() : '';
	const accountNumber = typeof value.account_number === 'string' ? value.account_number.trim() : '';
	const amount = parsePendingAmount(value.amount);
	if (!id || !accountNumber || amount === null) return null;
	const createdAt = parsePendingTimestamp(value.created_at, new Date().toISOString());
	const unit = Number(value.unit);
	return {
		id,
		account_number: accountNumber,
		account_name: typeof value.account_name === 'string' ? value.account_name : '',
		broker_name: typeof value.broker_name === 'string' ? value.broker_name : '',
		unit: Number.isFinite(unit) ? unit : 0,
		amount,
		note: normalizePendingNote(value.note),
		withdrawn_at: parsePendingTimestamp(value.withdrawn_at, createdAt),
		created_at: createdAt
	};
}

export function normalizePendingWithdrawals(raw: unknown): PendingWithdrawal[] {
	if (!Array.isArray(raw)) return [];
	return raw
		.map(normalizePendingWithdrawal)
		.filter((item): item is PendingWithdrawal => item !== null);
}

export function createPendingWithdrawalId(): string {
	return crypto.randomUUID();
}
