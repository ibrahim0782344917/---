#!/usr/bin/env python3
"""Extract a small, real Baghdad OSM POI preview from Geofabrik Iraq snapshot.

No private user data is read. Public ODbL places MUST retain attribution.
No store/account/product records are created by this script.
"""
import argparse
import hashlib
import json

import osmium

LABELS = {
    "supermarket": "سوبرماركت", "convenience": "بقالة",
    "clothes": "ملابس", "bakery": "مخبز", "shoes": "أحذية",
    "mobile_phone": "موبايلات", "electronics": "إلكترونيات",
    "restaurant": "مطعم", "cafe": "مقهى", "fast_food": "وجبات سريعة",
    "pharmacy": "صيدلية", "clinic": "عيادة", "fuel": "محطة وقود",
    "marketplace": "سوق", "hardware": "مواد بناء",
    "beauty": "تجميل", "furniture": "أثاث",
}
AMENITIES = {"restaurant", "cafe", "fast_food", "pharmacy", "clinic", "fuel", "marketplace"}

class Collector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.places = {}

    def accept(self, osm_id, lat, lon, tags):
        if not (32.98 <= lat <= 33.70 and 44.02 <= lon <= 44.90):
            return
        name = (tags.get("name:ar") or tags.get("name") or tags.get("name:en") or "").strip()
        if not (2 <= len(name) <= 145):
            return
        shop = tags.get("shop")
        amenity = tags.get("amenity")
        if not shop and amenity not in AMENITIES:
            return
        kind = shop or amenity
        category = LABELS.get(kind, "محل أو خدمة")
        city = tags.get("addr:city") or ""
        street = tags.get("addr:street") or ""
        address = "، ".join(filter(None, (street, city))) or "بغداد، العراق"
        self.places[osm_id] = {
            "osm_id": osm_id,
            "name": name,
            "category": category,
            "address": address[:170],
            "latitude": round(lat, 6),
            "longitude": round(lon, 6),
        }

    def node(self, n):
        try:
            if n.location.valid():
                self.accept(f"node/{n.id}", n.location.lat, n.location.lon, n.tags)
        except (ValueError, RuntimeError):
            pass

    def way(self, w):
        if not (w.tags.get("shop") or w.tags.get("amenity") in AMENITIES):
            return
        coords = []
        for point in w.nodes:
            try:
                if point.location.valid():
                    coords.append((point.location.lat, point.location.lon))
            except (ValueError, RuntimeError):
                pass
        if coords:
            self.accept(
                f"way/{w.id}",
                sum(p[0] for p in coords) / len(coords),
                sum(p[1] for p in coords) / len(coords),
                w.tags,
            )

def select_diverse(places, limit):
    # Spread points around Baghdad neighbourhoods; avoid 700 near one road.
    groups = {}
    for obj in places:
        tile = (int(obj["latitude"] * 90), int(obj["longitude"] * 90))
        groups.setdefault(tile, []).append(obj)
    for group in groups.values():
        group.sort(key=lambda x: hashlib.sha256(x["osm_id"].encode()).digest())
    keys = sorted(groups)
    result = []
    while keys and len(result) < limit:
        keys_next = []
        for key in keys:
            if len(result) >= limit:
                break
            group = groups[key]
            result.append(group.pop())
            if group:
                keys_next.append(key)
        keys = keys_next
    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pbf")
    ap.add_argument("--limit", type=int, default=850)
    args = ap.parse_args()
    handler = Collector()
    handler.apply_file(args.pbf, locations=True)
    chosen = select_diverse(list(handler.places.values()), args.limit)
    print("SHITREED_OSM_STATS=" + json.dumps({
        "total_named_baghdad": len(handler.places),
        "selected": len(chosen),
        "source": "Geofabrik Iraq OSM PBF",
        "attribution": "© OpenStreetMap contributors",
    }, ensure_ascii=False, separators=(",", ":")))
    for place in chosen:
        print("SHITREED_OSM_POI=" +
              json.dumps(place, ensure_ascii=False, separators=(",", ":")))

if __name__ == "__main__":
    main()
