const REQUIRED_ENV_VARS = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'N8N_ROSTER_EMAIL_WEBHOOK_URL'
];

function json(statusCode, body, origin = '*') {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Allow-Methods': 'POST, OPTIONS'
    },
    body: JSON.stringify(body)
  };
}

function getAllowedOrigin(event) {
  return process.env.EMAIL_PROXY_ALLOWED_ORIGIN || event.headers.origin || '*';
}

function parseRecipients(recipients) {
  const values = Array.isArray(recipients) ? recipients : [];
  const seen = new Set();
  const valid = [];
  values.forEach(value => {
    const email = String(value || '').trim().toLowerCase();
    if (!email) return;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return;
    if (seen.has(email)) return;
    seen.add(email);
    valid.push(email);
  });
  return valid;
}

async function getSupabaseUser(accessToken) {
  const response = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: process.env.SUPABASE_ANON_KEY,
      Authorization: `Bearer ${accessToken}`
    }
  });

  if (!response.ok) {
    return null;
  }

  return response.json();
}

async function loadApprovalRow(userId) {
  const url = new URL(`${process.env.SUPABASE_URL}/rest/v1/approved_users`);
  url.searchParams.set('select', 'user_id,email,approved,is_admin');
  url.searchParams.set('user_id', `eq.${userId}`);
  url.searchParams.set('limit', '1');

  const response = await fetch(url, {
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
      Accept: 'application/json'
    }
  });

  if (!response.ok) {
    throw new Error('Could not verify admin access in Supabase.');
  }

  const rows = await response.json();
  return rows[0] || null;
}

exports.handler = async event => {
  const origin = getAllowedOrigin(event);

  if (event.httpMethod === 'OPTIONS') {
    return json(204, {}, origin);
  }

  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'Method not allowed.' }, origin);
  }

  const missingEnv = REQUIRED_ENV_VARS.filter(name => !process.env[name]);
  if (missingEnv.length) {
    return json(500, { error: `Missing Netlify env vars: ${missingEnv.join(', ')}` }, origin);
  }

  const authHeader = event.headers.authorization || event.headers.Authorization || '';
  const accessToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!accessToken) {
    return json(401, { error: 'Missing Supabase access token.' }, origin);
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch {
    return json(400, { error: 'Request body must be valid JSON.' }, origin);
  }

  const recipients = parseRecipients(payload.recipients);
  if (!recipients.length) {
    return json(400, { error: 'Provide at least one valid recipient email address.' }, origin);
  }

  if (!Array.isArray(payload.rows) || !payload.rows.length) {
    return json(400, { error: 'Roster rows are missing from the request.' }, origin);
  }

  const user = await getSupabaseUser(accessToken);
  if (!user?.id) {
    return json(401, { error: 'Could not verify the signed-in Supabase user.' }, origin);
  }

  let approvalRow;
  try {
    approvalRow = await loadApprovalRow(user.id);
  } catch (error) {
    return json(500, { error: error.message || 'Could not verify admin access.' }, origin);
  }

  if (!approvalRow?.approved || !approvalRow?.is_admin) {
    return json(403, { error: 'Only approved admin users can send roster emails.' }, origin);
  }

  const webhookHeaders = {
    'Content-Type': 'application/json'
  };
  if (process.env.N8N_ROSTER_EMAIL_WEBHOOK_SECRET) {
    webhookHeaders['x-roster-webhook-secret'] = process.env.N8N_ROSTER_EMAIL_WEBHOOK_SECRET;
  }

  const webhookBody = {
    source: 'roster-dashboard-pro',
    actor: {
      user_id: user.id,
      email: approvalRow.email || user.email || ''
    },
    recipients,
    month: payload.month || '',
    monthTitle: payload.monthTitle || '',
    includeNotes: payload.includeNotes === true,
    generatedAt: payload.generatedAt || new Date().toISOString(),
    rows: payload.rows
  };

  const webhookResponse = await fetch(process.env.N8N_ROSTER_EMAIL_WEBHOOK_URL, {
    method: 'POST',
    headers: webhookHeaders,
    body: JSON.stringify(webhookBody)
  });

  const responseText = await webhookResponse.text();
  if (!webhookResponse.ok) {
    return json(502, {
      error: responseText || 'The n8n webhook rejected the roster email request.'
    }, origin);
  }

  return json(200, {
    ok: true,
    message: `Roster email request forwarded for ${recipients.length} recipient${recipients.length === 1 ? '' : 's'}.`
  }, origin);
};
