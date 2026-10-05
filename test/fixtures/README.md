# Test fixtures

`snapshot/` is a real snapshot, cut down from a full run's `tmp/snapshot/` on 2026-10-02 to a few packages of each dataset, chosen for the naming schemes they exercise:

| Dataset | Packages |
|---|---|
| NBD | Iowa; national |
| NHD | HU-8 05120101; District of Columbia |
| NHDPlus HR | HU-4 0108, with its rasters |
| WBD | HU-2 01 |
| 3DHP | Both CONUS editions, FY25 and FY26 |
| Map Indices, NSD, NTD, Woodland | Iowa |
| GNIS | Iowa's Domestic Names and Full Model; All Names; Iowa's 2017 gazetteer file, which is on `geonames.usgs.gov` |
| Small-scale | State boundaries |
| Contours | Aberdeen E, South Dakota; Montreal E, Quebec; Brandon W, an older tile named by number |
| Topo Map Vector Data | Washington West, DC; Albany E, a retired 1 x 1 degree package |

The files are plain JSON lines, which the harvester reads like a full snapshot's gzipped ones:
- `products.jsonl`: the catalog's products, one per line.
- `bucket.jsonl`: `[key, size]` for each listed object: the packages' files and the thumbnails and metadata beside them.
- `remote.jsonl`: `[url, available, size]` for each file checked elsewhere.
