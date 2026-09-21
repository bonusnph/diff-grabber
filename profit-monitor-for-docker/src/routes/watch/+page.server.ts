export const load = async ({ fetch }: { fetch: typeof globalThis.fetch }) => {
	try {
		const response = await fetch('/api/data');
		if (!response.ok) return { initial: null };
		const payload = await response.json();
		if (payload?.error) return { initial: null };
		return { initial: payload };
	} catch {
		return { initial: null };
	}
};
