# gov.usgs.tnm

This repository contains [OpenGeoMetadata Aardvark](https://opengeometadata.org/ogm-aardvark/) records for the vector data that the U.S. Geological Survey distributes through [The National Map](https://www.usgs.gov/programs/national-geospatial-program/national-map): boundaries, hydrography, transportation, structures, geographic names, contours, map indices and woodland, and the combined vector data behind every US Topo map. There is one record per downloadable package, plus a collection record for each of the 13 datasets.

The records are generated from The National Map's catalog and checked against its download server. This repository is not an official USGS product.

This metadata is provided under the [CC0 v1.0 License](LICENSE), which allows for free use and redistribution without restrictions. The data itself is in the U.S. public domain.

## Datasets

The National Map lists each format of a package as a separate product. The harvester groups them back into packages: one dataset for one area, in multiple formats.

| Dataset | Collection | Packaged by | Formats | Previews |
|---|---|---|---|---|
| Topo Map Vector Data (Combined Vector) | `usgs-tnm-vector` | 7.5-minute quadrangle | GeoPackage, file geodatabase, shapefile | None |
| National Hydrography Dataset (NHD) | `usgs-tnm-nhd` | HU-8 subbasin, HU-4 subregion, state, national | GeoPackage, file geodatabase, shapefile | `nhd` map service |
| 1/3 Arc-Second Contours | `usgs-tnm-contours` | 1 x 1 degree tile, national | GeoPackage, file geodatabase, shapefile | `contours` map service |
| NHDPlus High Resolution | `usgs-tnm-nhdplushr` | HU-4 subregion, HU-8 subbasin, national release | GeoPackage, file geodatabase, rasters | `NHDPlus_HR` map service |
| Geographic Names Information System (GNIS) | `usgs-tnm-gnis` | State, all states, national, by kind of file | Pipe-delimited text, GeoPackage, file geodatabase | `geonames` map service |
| National Boundary Dataset (NBD) | `usgs-tnm-nbd` | State, national | GeoPackage, file geodatabase, shapefile | `govunits` map service |
| National Structures Dataset (NSD) | `usgs-tnm-nsd` | State, national | GeoPackage, file geodatabase, shapefile | `structures` map service |
| National Transportation Dataset (NTD) | `usgs-tnm-ntd` | State, national | GeoPackage, file geodatabase, shapefile | `transportation` map service |
| Map Indices | `usgs-tnm-mapindices` | State, national | File geodatabase, shapefile | `map_indices` map service |
| Woodland Tint | `usgs-tnm-woodland` | State, national | File geodatabase, shapefile | None |
| Watershed Boundary Dataset (WBD) | `usgs-tnm-wbd` | HU-2 region, national | GeoPackage, file geodatabase, shapefile | `wbd` map service |
| Small-scale Datasets (1:1,000,000) | `usgs-tnm-smallscale` | National | File geodatabase, shapefile | None |
| 3D Hydrography Program (3DHP) | `usgs-tnm-3dhp` | Conterminous U.S. and Alaska, by annual edition | GeoPackage, file geodatabase | `3DHP_all` map service |

Map services are The National Map's own ArcGIS services at `carto.nationalmap.gov` and `hydro.nationalmap.gov`. They draw the whole country, so a record's preview shows the dataset everywhere in view, not just within the package.

## File Structure

```
metadata-aardvark/
  nbd/
    usgs-tnm-nbd.json                      the collection record
    usgs-tnm-nbd-ia.json                   one record per package, named by its id
    ...
  nhd/
    usgs-tnm-nhd-ia.json                   state and national packages
    05/
      usgs-tnm-nhd-hu8-05120101.json       hydrologic units, by their region
      ...
  contours/
    sd/
      usgs-tnm-contours-sd-aberdeen-e.json tiles, by their state
      ...
  vector/
    47/
      usgs-tnm-vector-47611.json           quadrangles, by the thousands of their GNIS cell
      ...
  ...
withdrawn.json                             records that have left the repository
```

Each dataset has a directory. NHD, the contours and Topo Map Vector Data have thousands of packages each, so their records are bucketed further, which keeps every directory within GitHub's 1,000-entry listing limit.

## Metadata

- **Version:** OGM Aardvark, with no custom fields.
- **Other formats:** each record links the package's original FGDC metadata, which USGS hosts; it isn't copied here.
- **Updates:** a GitHub Actions workflow rebuilds every record daily from The National Map's catalog. Files only change when USGS's metadata for a package does, so an unchanged catalog produces no commit.
- **Validation:** the tests in `test/` run before every harvest.

### Source

The harvester reads three things on each run:
- **The catalog:** every product listed under each dataset's tag in the [TNM Access API](https://tnmaccess.nationalmap.gov/api/v1/docs). One query can't page past about 166,000 products, so Topo Map Vector Data's 195,000 are fetched a format at a time, and the parts are checked against the dataset's total.
- **The download server:** a listing of the folders of USGS's `prd-tnm` S3 bucket that the catalog's files are in. It gives each file's size, which the catalog often gets wrong, and shows which files are gone: the catalog lists a few dozen files that no longer exist.
- **Files elsewhere:** GNIS's 2017 state gazetteer files are on `geonames.usgs.gov`, which can't be listed, so each is checked with a `HEAD` request. A redirect to anything but the same file counts as gone.

What it fetched is saved in `tmp/snapshot/`.

### Packages

The National Map names each file for the area it covers, in a scheme that differs by dataset. `package.rb` holds a pattern for each, which says what area a file covers and what format it is in; files of the same area are one package. Some details:
- **Formats:** a file's format comes from its name, or from its folder when the name doesn't say. If The National Map lists two files in one format for an area, the one published last is kept.
- **Quadrangles:** a quadrangle is its GNIS cell, not its file name. In a few cells the GeoPackage names the quadrangle differently from the other formats, or spells it differently; the record is named from the most recently published product.
- **URLs:** the catalog encodes a few file names twice, an apostrophe as `%2527` rather than `%27`, so URLs are decoded once more before use.
- **Editions:** NHDPlus HR file names sometimes carry the date of their edition. A subregion's files are one package whatever their dates. 3DHP's annual editions stay available side by side, so each is a package of its own.
- **Missing files:** files that aren't on the download server are left out. A package with none left gets no record; as of October 2026 there are 82, including the 62 GNIS gazetteer files.
- **Names:** a file whose name matches no pattern still becomes a package, named for its file, and the harvester reports how many there were.

### Collections

Each dataset has a collection record, e.g. `usgs-tnm-nhd`, with USGS's description of the dataset, its map service, and an extent, years and modification date summarizing its packages.

## Withdrawn Records

When a record leaves the repository, it is deleted and logged in `withdrawn.json`.

- **Quality:** if The National Map still lists the package but none of its files are on the download server, the entry's reason is `quality`.
- **Superseded:** if a later 3DHP edition of the same area has a record, the reason is `superseded`, with `is_replaced_by` naming it.
- **Upstream-removed:** otherwise, the reason is `upstream-removed`.
- **Republished:** entries are only removed when their package comes back.

The harvester stops without changing anything in three cases:
- A query's pages hold noticeably fewer products than the API says it has, or a dataset's parts don't add up to it.
- The catalog lists nothing at all for one of the datasets.
- The run would remove more than 2% of all records.

Set `FORCE=1` if the last two are intentional.

## Running the Harvester

The harvester needs Ruby 4.0, whose standard library has everything it uses.

```bash
ruby harvester.rb
```

These environment variables change how it runs:

- `SOURCE=tmp/snapshot` uses a previous run's snapshot instead of fetching anything.
- `DRY_RUN=1` reports what would change without writing anything.
- `FORCE=1` allows a run that would withdraw more than 2% of the records, or that finds a dataset empty.

To run the tests:

```bash
for test in test/*_test.rb; do ruby "$test"; done
```

Hydrologic units' names change rarely, and the hydrography service they come from is often down, so they're kept in `data/hydrologic-units.json` rather than fetched on every run. To refresh them:

```bash
ruby hydrologic_units.rb
```

The extents of the areas whose boxes circle the globe are kept in `data/extents.json`. To measure every area that needs one in the latest snapshot, and rewrite the file:

```bash
ruby extents.rb
```

## How to Contribute

For problems with the records, open an issue in this repository. Every record is regenerated from The National Map's catalog daily, so edits to the files would be overwritten:
- **How fields are mapped:** change `mapper.rb`, `datasets.rb` and `places.rb`.
- **How files are grouped into packages:** change the patterns in `package.rb`.
- **The catalog's own data:** corrections have to be made by USGS.
