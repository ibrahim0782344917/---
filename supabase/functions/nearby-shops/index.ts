// Google Places Nearby Search (New), isolated from the Flutter client.
// This endpoint exposes no API key and deliberately does not persist Places data.
// The public endpoint is limited to Baghdad, rate-limited per IP/minute, and
// requires a Google Cloud daily quota cap before production use.
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'apikey, authorization, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
})

const categories: Record<string, string> = {
  restaurant: 'مطعم',
  supermarket: 'سوبرماركت',
  grocery_store: 'بقالة',
  clothing_store: 'ملابس',
  electronics_store: 'إلكترونيات',
  cell_phone_store: 'موبايلات',
  shopping_mall: 'مول',
  pharmacy: 'صيدلية',
  hardware_store: 'مواد بناء',
  bakery: 'مخبز',
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const key = Deno.env.get('GOOGLE_PLACES_API_KEY')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!key || !supabaseUrl || !serviceKey) {
    return json({ error: 'Google Places is not configured' }, 503)
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch {
    return json({ error: 'Invalid request' }, 400)
  }
  const latitude = body.latitude
  const longitude = body.longitude
  if (typeof latitude !== 'number' || typeof longitude !== 'number' ||
    !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
    latitude < 32.9 || latitude > 33.7 || longitude < 43.8 || longitude > 44.9) {
    return json({ error: 'Only Baghdad coordinates are supported' }, 400)
  }

  try {
    // Rate limits apply BEFORE sending a billable Google request. The hashed
    // bucket changes daily. Do not trust an app-provided rate-limit identifier.
    const ip = (request.headers.get('x-forwarded-for') ??
      request.headers.get('cf-connecting-ip') ??
      'unidentified').split(',')[0].trim()
    const day = new Date().toISOString().slice(0, 10)
    const salt = Deno.env.get('GOOGLE_PLACES_RATE_SALT') ?? ''
    const digest = await crypto.subtle.digest(
      'SHA-256', new TextEncoder().encode(ip + ':' + day + ':' + salt),
    )
    const bucket = Array.from(new Uint8Array(digest))
      .map(b => b.toString(16).padStart(2, '0')).join('')
    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: allowed, error: quotaError } = await db.rpc(
      'try_consume_google_places_budget', { p_bucket: bucket },
    )
    if (quotaError) return json({ error: 'Places rate limiter not ready' }, 503)
    if (!allowed) return json({ error: 'Too many requests. Try later.' }, 429)

    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 8000)
    let googleResponse: Response
    try {
      googleResponse = await fetch('https://places.googleapis.com/v1/places:searchNearby', {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': key,
          'X-Goog-FieldMask': 'places.id,places.displayName,places.location,places.formattedAddress,places.primaryType',
        },
        body: JSON.stringify({
          includedTypes: [
            'store', 'supermarket', 'grocery_store', 'shopping_mall',
            'restaurant', 'pharmacy', 'clothing_store', 'electronics_store',
            'cell_phone_store', 'hardware_store', 'bakery',
          ],
          maxResultCount: 20,
          languageCode: 'ar',
          regionCode: 'IQ',
          rankPreference: 'DISTANCE',
          locationRestriction: { circle: {
            center: { latitude, longitude }, radius: 4500,
          } },
        }),
      })
    } finally {
      clearTimeout(timeout)
    }
    if (!googleResponse.ok) {
      console.error('Google Places status:', googleResponse.status)
      return json({ error: 'Places lookup failed' }, 502)
    }

    const result = await googleResponse.json()
    const places = (Array.isArray(result.places) ? result.places : [])
      .filter((place: Record<string, unknown>) =>
        typeof place.id === 'string' &&
        typeof (place.displayName as Record<string, unknown> | undefined)?.text === 'string' &&
        typeof (place.location as Record<string, unknown> | undefined)?.latitude === 'number' &&
        typeof (place.location as Record<string, unknown> | undefined)?.longitude === 'number',
      )
      .map((place: Record<string, any>) => ({
        id: place.id,
        name: place.displayName.text,
        address: typeof place.formattedAddress === 'string' ? place.formattedAddress : '',
        category: categories[place.primaryType] ?? 'محل على Google',
        latitude: place.location.latitude,
        longitude: place.location.longitude,
      }))
    return json({ places, source: 'Google Maps' })
  } catch (error) {
    console.error('Places proxy unavailable:', error instanceof Error ? error.name : 'Unknown')
    return json({ error: 'Places service unavailable' }, 503)
  }
})
