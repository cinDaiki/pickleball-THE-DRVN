// Initial development configuration. Credentials only live in function secrets.
export function emailConfig(env) {
  const provider = env('EMAIL_PROVIDER') || 'gmail';
  const user = env('GMAIL_USER') || 'xdqwerts@gmail.com';
  const mode = env('EMAIL_MODE') || 'test';
  return {
    provider, user, mode,
    configured: provider === 'gmail'
      ? !!env('GMAIL_APP_PASSWORD')
      : provider === 'resend' && !!(env('RESEND_API_KEY') && env('EMAIL_FROM')),
    allowed: (env('EMAIL_TEST_RECIPIENTS') || user).split(',').map(v => v.trim().toLowerCase()).filter(Boolean)
  };
}
export function checkRecipient(config, recipient) {
  if (!config.configured) throw Error('Email delivery credentials are missing');
  if (config.mode !== 'production' && !config.allowed.includes(recipient.toLowerCase())) {
    throw Error('Test mode: recipient is not in EMAIL_TEST_RECIPIENTS');
  }
}
export async function deliverEmail(env, {to, subject, text, id}) {
  const config = emailConfig(env);
  checkRecipient(config, to);
  if (config.provider === 'gmail') {
    const { default: nodemailer } = await import('npm:nodemailer@10.0.15');
    const transport = nodemailer.createTransport({
      host: 'smtp.gmail.com', port: 465, secure: true,
      auth: { user: config.user, pass: env('GMAIL_APP_PASSWORD') },
      connectionTimeout: 10000, greetingTimeout: 10000, socketTimeout: 20000,
      logger: false, debug: false
    });
    try {
      const result = await transport.sendMail({
        from: { name: 'The DRVN', address: config.user }, to,
        subject: config.mode === 'production' ? subject : '[TEST] ' + subject,
        text, messageId: `<drvn-${id}@${config.user.split('@')[1]}>`,
        replyTo: env('EMAIL_REPLY_TO') || config.user
      });
      if (!result.accepted?.length) throw Error('Email provider did not accept the message');
      return result.messageId;
    } catch {
      throw Error('Gmail delivery failed. Check account authorization and provider delivery history before retrying.');
    } finally { transport.close(); }
  }
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env('RESEND_API_KEY')}`, 'Content-Type': 'application/json', 'Idempotency-Key': id },
    body: JSON.stringify({from: env('EMAIL_FROM'), to: [to], subject: config.mode === 'production' ? subject : '[TEST] ' + subject, text,
      ...(env('EMAIL_REPLY_TO') ? {reply_to: env('EMAIL_REPLY_TO')} : {})})
  });
  const result = await response.json();
  if (!response.ok) throw Error('Email provider rejected delivery');
  return result.id;
}
