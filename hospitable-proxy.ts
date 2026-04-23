// Supabase Edge Function: hospitable-proxy
// Paste this into: Supabase Dashboard → Edge Functions → hospitable-proxy → Edit → Deploy

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey, x-client-info',
}

const ALLOWED_PREFIXES = [
  '/properties',
  '/reservations',
  '/reviews',
  '/conversations',
  '/listings',
  '/customers/me/properties',
  '/customers/me/reservations',
  '/customers/me/reviews',
]

const HOSPITABLE_BASE = 'https://public.api.hospitable.com/v2'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS })
  if (req.method !== 'GET') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('No authorization header')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Verify caller's JWT → get their user id
    const { data: { user }, error: authErr } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    )
    if (authErr || !user) throw new Error('Unauthorized')

    // Look up their workspace
    const { data: profile } = await supabase
      .from('profiles').select('workspace_id').eq('id', user.id).single()
    if (!profile) throw new Error('Profile not found')

    // PAT: prefer per-workspace key stored in DB, fall back to env secret
    const { data: workspace } = await supabase
      .from('workspaces').select('hosp_pat').eq('id', profile.workspace_id).single()
    const pat = workspace?.hosp_pat || Deno.env.get('HOSPITABLE_PAT')
    if (!pat) throw new Error('Hospitable API key not configured — paste your PAT on the Integrations page')

    // Validate path
    const reqUrl  = new URL(req.url)
    const path    = reqUrl.searchParams.get('path') || '/properties'
    const allowed = ALLOWED_PREFIXES.some(p => path.startsWith(p))
    if (!allowed) throw new Error('Path not allowed: ' + path)

    // Build query string — preserve bracket notation for array params
    const parts: string[] = []
    for (const [key, value] of reqUrl.searchParams.entries()) {
      if (key === 'path') continue
      const encodedKey = encodeURIComponent(key)
        .replace(/%5B/gi, '[').replace(/%5D/gi, ']').replace(/%2C/gi, ',')
      parts.push(`${encodedKey}=${encodeURIComponent(value)}`)
    }
    const qs        = parts.join('&')
    const targetUrl = HOSPITABLE_BASE + path + (qs ? '?' + qs : '')

    console.log('[hospitable-proxy] ->', targetUrl)

    const hospRes = await fetch(targetUrl, {
      headers: {
        'Authorization': `Bearer ${pat}`,
        'Content-Type':  'application/json',
        'Accept':        'application/json',
      }
    })

    const body = await hospRes.text()
    console.log('[hospitable-proxy] status:', hospRes.status)

    return new Response(body, {
      status:  hospRes.status,
      headers: { ...CORS, 'Content-Type': hospRes.headers.get('Content-Type') || 'application/json' }
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
    })
  }
})
