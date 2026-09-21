import nodemailer from 'nodemailer';

function smtpConfig() {
	const user = (process.env.SMTP_USER || '').trim();
	const pass = (process.env.SMTP_PASS || '').trim();
	const host = (process.env.SMTP_HOST || 'smtp.gmail.com').trim();
	const port = Number(process.env.SMTP_PORT || 587);
	const from = (process.env.SMTP_FROM || user).trim();
	return { user, pass, host, port, from };
}

export async function sendAlertEmail(
	to: string,
	payload: { subject: string; text: string; html?: string }
): Promise<boolean> {
	const { user, pass, host, port, from } = smtpConfig();
	if (!user || !pass || !to) {
		console.error('PL alert email skipped: SMTP_USER/SMTP_PASS or recipient is missing');
		return false;
	}

	const transporter = nodemailer.createTransport({
		host,
		port,
		secure: port === 465,
		auth: { user, pass }
	});

	try {
		await transporter.sendMail({
			from,
			to,
			subject: payload.subject,
			text: payload.text,
			html: payload.html
		});
		return true;
	} catch (error) {
		console.error('PL alert email failed:', error);
		return false;
	}
}
