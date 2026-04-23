// Supabase Edge Function: hospitable-proxy
// Deploy: Supabase Dashboard → Edge Functions → New Function → name: "hospitable-proxy" → paste this code
//
// This function:
//   1. Verifies the caller's Supabase JWT
//   2. Looks up their workspace's saved Hospitable PAT
//   3. Proxies the request to api.hospitable.com
//   4. Returns the response (handles CORS for browser requests)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('No authorization header')

    // Use service role to look up workspace PAT (bypasses RLS safely)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Verify the caller's JWT → get their user id
    const { data: { user }, error: authErr } = await supabase.auth.getUser(
      authHeader.replace('Bearer ', '')
    )
    if (authErr || !user) throw new Error('Unauthorized')

    // Look up their workspace
    const { data: profile, error: profErr } = await supabase
      .from('profiles')
      .select('workspace_id')
      .eq('id', user.id)
      .single()
    if (profErr || !profile) throw new Error('Profile not found')

    // Fetch the PAT stored for this workspace
    const { data: workspace, error: wsErr } = await supabase
      .from('workspaces')
      .select('hosp_pat')
      .eq('id', profile.workspace_id)
      .single()
    if (wsErr || !workspace?.hosp_pat) throw new Error('Hospitable API key not configured — paste your PAT on the Integrations page first')

    // Forward request to Hospitable API
    const reqUrl = new URL(req.url)
    const path   = reqUrl.searchParams.get('path') || '/properties'
    const fwdParams = new URLSearchParams()
    for (const [k, v] of reqUrl.searchParams.entries()) {
      if (k !== 'path') fwdParams.set(k, v)
    }

    const hospUrl = `https://api.hospitable.com/v1${path}${fwdParams.toString() ? '?' + fwdParams : ''}`
    const hospRes = await fetch(hospUrl, {
      headers: {
        'Authorization': `Bearer ${workspace.hosp_pat}`,
        'Content-Type':  'application/json',
        'Accept':        'application/json',
      }
    })

    const body = await hospRes.text()
    return new Response(body, {
      status:  hospRes.status,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), {
      status:  400,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    })
  }
})
