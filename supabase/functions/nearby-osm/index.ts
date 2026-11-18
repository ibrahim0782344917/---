// Shitreed: small-scale OpenStreetMap (Overpass) discovery PREVIEW for Iraq.
// OSM data © OpenStreetMap contributors (ODbL). Discovering a shop here does
// not imply it has registered, been verified or has products for sale.
// Public Overpass is NOT a commercial SLA; use licensed/self-hosted OSM data
// provider and tile hosting before general public launch.
import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
}
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
})

// The first public endpoint rejected Supabase Edge traffic with HTTP 406.
// Use the independently operated public Private.coffee instance for tiny previews.
// Commercial launch still requires a dedicated/contracted provider.
const overpass = 'https://overpass.private.coffee/api/interpreter'
const labels: Record<string, string> = {
  supermarket: 'سوبرماركت', convenience: 'بقالة', grocery: 'مواد غذائية',
  clothes: 'ملابس', shoes: 'أحذية', mobile_phone: 'موبايلات',
  electronics: 'إلكترونيات', beauty: 'تجميل', bakery: 'مخبز',
  hardware: 'عدد ومواد بناء', furniture: 'أثاث', general: 'محل عام',
  restaurant: 'مطعم', cafe: 'مقهى', fast_food: 'وجبات سريعة',
  pharmacy: 'صيدلية', bank: 'مصرف', clinic: 'عيادة', fuel: 'محطة وقود',
  marketplace: 'سوق',
}
type RecordValue = Record<string, unknown>
const asRecord = (v: unknown): RecordValue =>
  v !== null && typeof v === 'object' && !Array.isArray(v)
    ? v as RecordValue : {}
const validName = (name: unknown) => typeof name === 'string'
  && name.trim().length >= 2 && name.trim().length <= 110

function parseElements(raw: unknown) {
  const elements = asRecord(raw).elements
  if (!Array.isArray(elements)) return []
  const seen = new Set<string>()
  const places: Array<{id: string; name: string; address: string; category: string; latitude: number; longitude: number}> = []
  for (const element of elements) {
    const e = asRecord(element)
    const tags = asRecord(e.tags)
    const fallbackName = tags['name:ar'] ?? tags.name ?? tags['name:en']
    if (!validName(fallbackName)) continue
    const type = e.type
    const osmId = e.id
    if (!['node','way','relation'].includes(String(type)) ||
        (typeof osmId !== 'number' && typeof osmId !== 'string')) continue
    const unique = String(type) + '/' + String(osmId)
    if (seen.has(unique)) continue
    const center = asRecord(e.center)
    const lat = e.lat ?? center.lat
    const lon = e.lon ?? center.lon
    if (typeof lat !== 'number' || typeof lon !== 'number' ||
        !Number.isFinite(lat) || !Number.isFinite(lon) ||
        lat < 29 || lat > 37.7 || lon < 38.5 || lon > 48.9) continue
    const kind = String(tags.shop ?? tags.amenity ?? 'general')
    const street = typeof tags['addr:street'] === 'string' ? tags['addr:street'] : ''
    const city = typeof tags['addr:city'] === 'string' ? tags['addr:city'] : ''
    const address = [street, city].filter(Boolean).join('، ')
    seen.add(unique)
    places.push({
      id: unique, name: String(fallbackName).trim(),
      address: address || 'العراق',
      category: labels[kind] ?? 'محل أو خدمة',
      latitude: lat, longitude: lon,
    })
    if (places.length >= 50) break
  }
  return places
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json({ code: 'METHOD_NOT_ALLOWED' }, 405)
  if (Number(req.headers.get('content-length') ?? '0') > 2048) {
    return json({ code: 'INVALID_REQUEST' }, 400)
  }
  let body: RecordValue
  try { body = asRecord(await req.json()) }
  catch { return json({ code: 'INVALID_REQUEST' }, 400) }
  const latitude = body.latitude, longitude = body.longitude
  if (typeof latitude !== 'number' || typeof longitude !== 'number' ||
      !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < 29 || latitude > 37.7 || longitude < 38.5 || longitude > 48.9) {
    return json({ code: 'OUTSIDE_IRAQ_DISCOVERY_AREA' }, 400)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) return json({ code: 'SERVER_NOT_CONFIGURED' }, 503)

  try {
    // Never trust client-provided location identifiers or IP for authorization.
    // IP bucketing is best effort; a strict independent daily quota protects
    // public Overpass even if source IP headers are spoofed.
    const ip = (req.headers.get('x-forwarded-for') ??
      req.headers.get('cf-connecting-ip') ?? 'unidentified').split(',')[0].trim().slice(0,90)
    const digest = await crypto.subtle.digest('SHA-256',
      new TextEncoder().encode(ip + ':' + new Date().toISOString().slice(0,10) + ':' + serviceKey))
    const bucket = Array.from(new Uint8Array(digest)).map(x => x.toString(16).padStart(2,'0')).join('')
    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    // Prefer the locally indexed, ODbL-attributed Iraq directory whenever
    // it has nearby places. This avoids calling a public Overpass server at
    // every tap; it is read-only and distinct from verified Shitreed stores.
    const padLat = 0.020, padLon = 0.025
    const {data: localPlaces, error: directoryError} = await db
      .from('shitreed_osm_directory')
      .select('osm_id,name,category,address,latitude,longitude')
      .gte('latitude', latitude - padLat)
      .lte('latitude', latitude + padLat)
      .gte('longitude', longitude - padLon)
      .lte('longitude', longitude + padLon)
      .limit(800)
    if (!directoryError && Array.isArray(localPlaces) && localPlaces.length > 0) {
      const radians = (deg: number) => deg * Math.PI / 180
      const nearby = localPlaces
        .map((p) => {
          const dLat = radians(p.latitude - latitude)
          const dLon = radians(p.longitude - longitude)
          const half = Math.sin(dLat / 2) ** 2 +
            Math.cos(radians(latitude)) * Math.cos(radians(p.latitude)) *
            Math.sin(dLon / 2) ** 2
          const meters = 6371000 * 2 * Math.asin(Math.min(1, Math.sqrt(half)))
          return {place: p, meters}
        })
        .filter((v) => v.meters <= 1800)
        .sort((a,b) => a.meters - b.meters)
        .slice(0,50)
        .map((v) => ({
          id:v.place.osm_id,
          name:v.place.name, address:v.place.address,
          category:v.place.category,
          latitude:v.place.latitude, longitude:v.place.longitude,
        }))
      if (nearby.length > 0) {
        return json({
          places: nearby,
          source: 'OpenStreetMap',
          attribution: '© OpenStreetMap contributors',
          scope: 'discovery_only_not_verified_for_purchase',
          provider: 'Shitreed OSM directory snapshot',
        })
      }
    }
    if (directoryError) {
      console.warn('Local OSM directory lookup unavailable')
    }
    const {data: allowed, error: rateError} = await db.rpc(
      'try_consume_shitreed_osm_quota', {p_bucket: bucket})
    if (rateError) return json({ code: 'RATE_LIMIT_UNAVAILABLE' }, 503)
    if (!allowed) return json({ code: 'RATE_LIMIT_EXCEEDED' }, 429)

    const lat = latitude.toFixed(5), lon = longitude.toFixed(5)
    const query = '[out:json][timeout:12];(' +
      'nwr["shop"](around:1600,' + lat + ',' + lon + ');' +
      'nwr["amenity"~"^(restaurant|cafe|fast_food|pharmacy|clinic|bank|fuel|marketplace)$"]' +
      '(around:1600,' + lat + ',' + lon + ');' +
      ');out center 60;'
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 18000)
    try {
      const upstream = await fetch(overpass, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent': 'Shitreed-PlacesPreview/0.1 (https://pixer-laravel.com)',
        },
        body: new URLSearchParams({data: query}),
        signal: controller.signal,
      })
      if (!upstream.ok) {
        console.warn('Overpass responded with', upstream.status)
        return json({
          code: upstream.status === 429 ? 'UPSTREAM_BUSY' : 'UPSTREAM_UNAVAILABLE',
        }, 503)
      }
      const bodyText = await upstream.text()
      if (bodyText.length > 650000) return json({code:'RESULT_TOO_LARGE'},502)
      const places = parseElements(JSON.parse(bodyText))
      return json({
        places, source: 'OpenStreetMap',
        attribution: '© OpenStreetMap contributors',
        scope: 'discovery_only_not_verified_for_purchase',
      })
    } finally { clearTimeout(timeout) }
  } catch (err) {
    console.warn('OSM discovery failed', err instanceof Error ? err.name : 'unknown')
    return json({ code: 'UPSTREAM_UNAVAILABLE' }, 503)
  }
})
