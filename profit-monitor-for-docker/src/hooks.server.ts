import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	const response = await resolve(event);
	const type = response.headers.get('content-type') || '';
	if (type.includes('text/html')) {
		response.headers.set('cache-control', 'no-cache, no-store, must-revalidate');
	}
	return response;
};
