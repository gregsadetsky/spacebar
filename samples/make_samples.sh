#!/bin/bash
# generates samples/*.geojson and samples/*.sqlite3. deterministic, no downloads.
# HUGE=1 also writes huge.sqlite3 (~200 MB) to test the size cap.
set -euo pipefail
cd "$(dirname "$0")"

python3 -I - <<'PY'
import json, random

cities = [
  ("Tokyo","JP",37400068,139.69,35.69),("Delhi","IN",28514000,77.21,28.61),("Shanghai","CN",25582000,121.47,31.23),
  ("São Paulo","BR",21650000,-46.63,-23.55),("Mexico City","MX",21581000,-99.13,19.43),("Cairo","EG",20076000,31.24,30.04),
  ("Mumbai","IN",19980000,72.88,19.08),("Beijing","CN",19618000,116.40,39.90),("Dhaka","BD",19578000,90.41,23.81),
  ("Osaka","JP",19281000,135.50,34.69),("New York","US",18819000,-74.01,40.71),("Karachi","PK",15400000,67.01,24.86),
  ("Buenos Aires","AR",14967000,-58.38,-34.60),("Istanbul","TR",14751000,28.98,41.01),("Kolkata","IN",14681000,88.36,22.57),
  ("Manila","PH",13482000,120.98,14.60),("Lagos","NG",13463000,3.38,6.52),("Rio de Janeiro","BR",13293000,-43.17,-22.91),
  ("Kinshasa","CD",13171000,15.27,-4.32),("Los Angeles","US",12458000,-118.24,34.05),("Moscow","RU",12410000,37.62,55.75),
  ("Paris","FR",10901000,2.35,48.86),("London","GB",9046000,-0.13,51.51),("Lima","PE",10391000,-77.04,-12.05),
  ("Bangkok","TH",10156000,100.50,13.76),("Seoul","KR",9963000,126.98,37.57),("Nagoya","JP",9507000,136.91,35.18),
  ("Jakarta","ID",10517000,106.85,-6.21),("Chicago","US",8864000,-87.63,41.88),("Tehran","IR",8896000,51.39,35.69),
  ("Bogotá","CO",10574000,-74.07,4.71),("Lahore","PK",11738000,74.35,31.55),("Johannesburg","ZA",5635000,28.05,-26.20),
  ("Madrid","ES",6497000,-3.70,40.42),("Toronto","CA",6082000,-79.38,43.65),("Singapore","SG",5792000,103.82,1.35),
  ("Sydney","AU",4926000,151.21,-33.87),("Melbourne","AU",4771000,144.96,-37.81),("Berlin","DE",3552000,13.40,52.52),
  ("Rome","IT",4210000,12.50,41.90),("Montreal","CA",4221000,-73.57,45.50),("Nairobi","KE",4386000,36.82,-1.29),
  ("Cape Town","ZA",4430000,18.42,-33.93),("Casablanca","MA",3684000,-7.59,33.57),("Oslo","NO",1041000,10.75,59.91),
  ("Stockholm","SE",1583000,18.07,59.33),("Helsinki","FI",1279000,24.94,60.17),("Reykjavik","IS",216000,-21.94,64.15),
  ("Anchorage","US",288000,-149.90,61.22),("Honolulu","US",350000,-157.86,21.31),("Auckland","NZ",1467000,174.76,-36.85),
  ("Santiago","CL",6680000,-70.67,-33.45),("Lisbon","PT",2927000,-9.14,38.72),("Dublin","IE",1201000,-6.26,53.35),
  ("Vienna","AT",1901000,16.37,48.21),("Warsaw","PL",1768000,21.01,52.23),("Athens","GR",3154000,23.73,37.98),
  ("Ulaanbaatar","MN",1520000,106.92,47.89),("Kathmandu","NP",1330000,85.32,27.72),("Havana","CU",2137000,-82.37,23.11),
  ("Quito","EC",1822000,-78.47,-0.18),("Ushuaia","AR",57000,-68.30,-54.80),("Longyearbyen","SJ",2400,15.63,78.22),
]
fc = {"type": "FeatureCollection", "features": [
  {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat]},
   "properties": {"name": n, "country": c, "population": p}} for n, c, p, lon, lat in cities]}
json.dump(fc, open("cities.geojson", "w"), ensure_ascii=False, indent=1)

shapes = {"type": "FeatureCollection", "name": "shapes", "features": [
  {"type": "Feature", "properties": {"name": "iberia-ish box", "kind": "polygon"},
   "geometry": {"type": "Polygon", "coordinates": [[[-9.5, 36.0], [3.3, 36.0], [3.3, 43.8], [-9.5, 43.8], [-9.5, 36.0]]]}},
  {"type": "Feature", "properties": {"name": "two islands, one with a lake", "kind": "multipolygon", "holes": 1},
   "geometry": {"type": "MultiPolygon", "coordinates": [
     [[[10.0, 54.0], [16.0, 54.0], [16.0, 58.0], [10.0, 58.0], [10.0, 54.0]], [[12.0, 55.0], [14.0, 55.0], [14.0, 57.0], [12.0, 55.0]]],
     [[[20.0, 60.0], [24.0, 60.0], [22.0, 63.0], [20.0, 60.0]]]]}},
  {"type": "Feature", "properties": {"name": "paris to istanbul", "kind": "line", "length_km": 2250},
   "geometry": {"type": "LineString", "coordinates": [[2.35, 48.86], [13.40, 52.52], [16.37, 48.21], [23.73, 37.98], [28.98, 41.01]]}},
  {"type": "Feature", "properties": {"name": "ferry routes", "kind": "multiline"},
   "geometry": {"type": "MultiLineString", "coordinates": [[[-6.26, 53.35], [-3.0, 53.4]], [[10.75, 59.91], [12.57, 55.68]]]}},
  {"type": "Feature", "properties": {"name": "capitals", "kind": "multipoint"},
   "geometry": {"type": "MultiPoint", "coordinates": [[-0.13, 51.51], [-3.70, 40.42], [12.50, 41.90]]}},
  {"type": "Feature", "properties": {"name": "mixed bag", "kind": "collection", "nested": {"a": [1, 2], "b": None}},
   "geometry": {"type": "GeometryCollection", "geometries": [
     {"type": "Point", "coordinates": [30.0, 50.0]},
     {"type": "LineString", "coordinates": [[30.0, 50.0], [35.0, 52.0]]}]}},
  {"type": "Feature", "properties": {"name": "no geometry"}, "geometry": None},
]}
json.dump(shapes, open("shapes.geojson", "w"), indent=1)

rng = random.Random(42)
big = {"type": "FeatureCollection", "features": [
  {"type": "Feature", "geometry": {"type": "Point", "coordinates": [round(rng.uniform(-180, 180), 4), round(rng.uniform(-60, 75), 4)]},
   "properties": {"i": i, "v": round(rng.random(), 3)}} for i in range(50000)]}
json.dump(big, open("big.geojson", "w"), separators=(",", ":"))

json.dump({"hello": "world", "items": [1, 2, 3], "nested": {"ok": True}}, open("invalid.geojson", "w"), indent=1)
print("geojson: cities, shapes, big, invalid")
PY

rm -f library.sqlite3 wal.sqlite3 wal.sqlite3-wal wal.sqlite3-shm notadb.sqlite3
sqlite3 library.sqlite3 < make_sqlite.sql
cp library.sqlite3 wal.sqlite3
sqlite3 wal.sqlite3 "PRAGMA journal_mode=WAL; INSERT INTO notes (body) VALUES ('written in wal mode, not yet checkpointed');"
# drop the sidecars: a wal-mode db copied without -wal/-shm is the nasty case,
# read-only open fails unless the host uses immutable=1
rm -f wal.sqlite3-wal wal.sqlite3-shm
printf 'this is not a database, just text with a .sqlite3 extension\n' > notadb.sqlite3
echo "sqlite: library, wal, notadb"

if [ "${HUGE:-0}" = "1" ]; then
  rm -f huge.sqlite3
  sqlite3 huge.sqlite3 "CREATE TABLE junk (id INTEGER PRIMARY KEY, blob BLOB);
    WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 2000)
    INSERT INTO junk (id, blob) SELECT n, randomblob(100000) FROM seq;"
  echo "sqlite: huge ($(du -h huge.sqlite3 | cut -f1))"
fi

# payload dump for the browser harness, when the cli has been built
CLI="../Packages/SpacebarKit/.build/debug/spacebar-cli"
if [ -x "$CLI" ]; then "$CLI" dump library.sqlite3 > library.sqlite3.json && echo "harness: library.sqlite3.json"; fi
ls -la *.geojson *.sqlite3*
