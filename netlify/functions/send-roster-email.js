const REQUIRED_ENV_VARS = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'N8N_ROSTER_EMAIL_WEBHOOK_URL'
];

const PUBLIC_SUPABASE_URL = 'https://xqfxkbzmrxrfnbrcivbd.supabase.co';
const PUBLIC_SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxZnhrYnptcnhyZm5icmNpdmJkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxODkyODgsImV4cCI6MjA5MTc2NTI4OH0.VHEZ6Dmqu1Wor74Cyqg8QtsY9cCuXE4TxBmQt5Nq-m0';

function getSupabaseUrl() {
  return process.env.SUPABASE_URL || PUBLIC_SUPABASE_URL;
}

function getSupabaseAnonKey() {
  return process.env.SUPABASE_ANON_KEY || PUBLIC_SUPABASE_ANON_KEY;
}

function log(stage, details = {}) {
  console.log(JSON.stringify({ stage, ...details }));
}

function logError(stage, error, details = {}) {
  console.error(JSON.stringify({
    stage,
    error: error?.message || String(error),
    ...details
  }));
}

function buildHeaders(origin = '*') {
  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
}

function json(statusCode, body, origin = '*') {
  return {
    statusCode,
    headers: buildHeaders(origin),
    body: JSON.stringify(body)
  };
}

function failure({ origin = '*', httpStatus = 500, stage, message, details = '', status = null }) {
  logError('error', new Error(message), { stage, httpStatus, status, details });
  return json(httpStatus, {
    ok: false,
    stage,
    message,
    ...(status !== null ? { status } : {}),
    ...(details ? { details } : {})
  }, origin);
}

function getAllowedOrigin(event) {
  const requestOrigin = event.headers.origin || event.headers.Origin || '';
  const configuredOrigin = process.env.EMAIL_PROXY_ALLOWED_ORIGIN || '';
  if (configuredOrigin) return configuredOrigin;
  if (requestOrigin && /^https?:\/\//i.test(requestOrigin)) return requestOrigin;
  return '*';
}

function parseRecipients(recipients) {
  const values = Array.isArray(recipients) ? recipients : [];
  const seen = new Set();
  const valid = [];
  const invalid = [];
  values.forEach(value => {
    const email = String(value || '').trim().toLowerCase();
    if (!email) return;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      invalid.push(value);
      return;
    }
    if (seen.has(email)) return;
    seen.add(email);
    valid.push(email);
  });
  return { valid, invalid };
}

function isApprovedAdmin(row) {
  if (!row || row.approved !== true) return false;
  if (row.is_admin === true) return true;
  if (row.admin === true) return true;
  if (String(row.role || '').toLowerCase() === 'admin') return true;
  return false;
}

async function getSupabaseUser(accessToken) {
  const response = await fetch(`${getSupabaseUrl()}/auth/v1/user`, {
    headers: {
      apikey: getSupabaseAnonKey(),
      Authorization: `Bearer ${accessToken}`
    }
  });

  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = null;
  }

  return {
    ok: response.ok,
    status: response.status,
    data,
    text
  };
}

async function loadApprovalRow(userId) {
  const selectAttempts = [
    'user_id,email,approved,is_admin',
    'user_id,email,approved,admin',
    'user_id,email,approved,role',
    '*'
  ];

  for (const select of selectAttempts) {
    const url = new URL(`${getSupabaseUrl()}/rest/v1/approved_users`);
    url.searchParams.set('select', select);
    url.searchParams.set('user_id', `eq.${userId}`);
    url.searchParams.set('limit', '1');

    const response = await fetch(url, {
      headers: {
        apikey: process.env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        Accept: 'application/json'
      }
    });

    const text = await response.text();
    let rows = [];
    try {
      rows = text ? JSON.parse(text) : [];
    } catch {
      rows = [];
    }

    if (response.ok) {
      return {
        ok: true,
        status: response.status,
        row: rows[0] || null,
        text,
        select
      };
    }

    if (!/column approved_users\./i.test(text)) {
      return {
        ok: false,
        status: response.status,
        row: null,
        text,
        select
      };
    }
  }

  return {
    ok: false,
    status: 500,
    row: null,
    text: 'Could not query approved_users with any supported admin column shape.',
    select: null
  };
}

exports.handler = async event => {
  log('function_invoked', { method: event.httpMethod, path: event.path || '' });
  const origin = getAllowedOrigin(event);
  log('cors_origin_checked', {
    requestOrigin: event.headers.origin || event.headers.Origin || '',
    allowedOrigin: origin
  });

  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 204,
      headers: buildHeaders(origin),
      body: ''
    };
  }

  if (event.httpMethod !== 'POST') {
    return failure({
      origin,
      httpStatus: 405,
      stage: 'function_invoked',
      message: 'Method not allowed.'
    });
  }

  const missingEnv = REQUIRED_ENV_VARS.filter(name => !process.env[name]);
  if (missingEnv.length) {
    return failure({
      origin,
      httpStatus: 500,
      stage: 'env_check',
      message: 'Required Netlify environment variables are missing.',
      details: missingEnv.join(', ')
    });
  }
  log('env_checked', {
    configured: REQUIRED_ENV_VARS,
    usingPublicSupabaseUrlFallback: !process.env.SUPABASE_URL,
    usingPublicSupabaseAnonFallback: !process.env.SUPABASE_ANON_KEY
  });

  const authHeader = event.headers.authorization || event.headers.Authorization || '';
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return failure({
      origin,
      httpStatus: 401,
      stage: 'auth',
      message: 'Missing or invalid Authorization header.'
    });
  }
  const accessToken = authHeader.slice(7).trim();
  if (!accessToken) {
    return failure({
      origin,
      httpStatus: 401,
      stage: 'auth',
      message: 'Missing Supabase access token.'
    });
  }
  log('auth_header_checked');

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (error) {
    return failure({
      origin,
      httpStatus: 400,
      stage: 'payload_validation',
      message: 'Request body must be valid JSON.',
      details: error.message
    });
  }

  const { valid: recipients, invalid: invalidRecipients } = parseRecipients(payload.recipients);
  if (!Array.isArray(payload.recipients) || !recipients.length) {
    return failure({
      origin,
      httpStatus: 400,
      stage: 'payload_validation',
      message: 'Recipients must be a non-empty array of valid email addresses.'
    });
  }
  if (invalidRecipients.length) {
    return failure({
      origin,
      httpStatus: 400,
      stage: 'payload_validation',
      message: 'One or more recipient email addresses are invalid.',
      details: invalidRecipients.join(', ')
    });
  }
  if (!Array.isArray(payload.rows)) {
    return failure({
      origin,
      httpStatus: 400,
      stage: 'payload_validation',
      message: 'Roster rows must be an array.'
    });
  }
  if (!payload.month && !payload.monthTitle) {
    return failure({
      origin,
      httpStatus: 400,
      stage: 'payload_validation',
      message: 'Month or monthTitle is required.'
    });
  }
  log('payload_validated', {
    recipientCount: recipients.length,
    rowCount: payload.rows.length,
    includeNotes: payload.includeNotes === true
  });

  const userResult = await getSupabaseUser(accessToken);
  if (!userResult.ok || !userResult.data?.id) {
    return failure({
      origin,
      httpStatus: 401,
      stage: 'auth',
      message: 'Could not verify the signed-in Supabase user.',
      status: userResult.status,
      details: userResult.text || 'Supabase auth lookup failed.'
    });
  }
  const user = userResult.data;
  log('supabase_user_verified', { userId: user.id, email: user.email || '' });

  const approvalResult = await loadApprovalRow(user.id);
  if (!approvalResult.ok) {
    return failure({
      origin,
      httpStatus: 500,
      stage: 'admin_check',
      message: 'Could not verify approved admin access in Supabase.',
      status: approvalResult.status,
      details: approvalResult.text || 'Approval lookup failed.'
    });
  }
  if (!isApprovedAdmin(approvalResult.row)) {
    return failure({
      origin,
      httpStatus: 403,
      stage: 'admin_check',
      message: 'Only approved admin users can send roster emails.'
    });
  }
  log('approved_user_checked', {
    userId: user.id,
    approved: approvalResult.row?.approved === true
  });

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
      email: approvalResult.row?.email || user.email || ''
    },
    recipients,
    month: payload.month || '',
    monthTitle: payload.monthTitle || '',
    includeNotes: payload.includeNotes === true,
    generatedAt: payload.generatedAt || new Date().toISOString(),
    rows: payload.rows
  };

  log('forwarding_to_n8n', {
    webhookConfigured: Boolean(process.env.N8N_ROSTER_EMAIL_WEBHOOK_URL),
    recipientCount: recipients.length,
    rowCount: payload.rows.length
  });

  let webhookResponse;
  try {
    webhookResponse = await fetch(process.env.N8N_ROSTER_EMAIL_WEBHOOK_URL, {
      method: 'POST',
      headers: webhookHeaders,
      body: JSON.stringify(webhookBody)
    });
  } catch (error) {
    return failure({
      origin,
      httpStatus: 502,
      stage: 'forward_to_n8n',
      message: 'Could not reach the n8n webhook.',
      details: error.message
    });
  }

  const responseText = await webhookResponse.text();
  log('n8n_response_received', { status: webhookResponse.status });
  if (!webhookResponse.ok) {
    return failure({
      origin,
      httpStatus: 502,
      stage: 'forward_to_n8n',
      message: 'n8n webhook returned a non-2xx response.',
      status: webhookResponse.status,
      details: responseText || 'No response body returned from n8n.'
    });
  }

  log('success', { recipientCount: recipients.length });
  return json(200, {
    ok: true,
    message: 'Roster email request sent',
    recipientCount: recipients.length
  }, origin);
};
