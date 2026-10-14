require 'minitest/autorun'
require 'json'
require 'stringio'
require_relative '../index_map'

# Index maps of the fixture snapshot's DEM tiles: see test/fixtures/README.md
class IndexMapTest < Minitest::Test
  FIXTURE = File.join(__dir__, 'fixtures', 'snapshot')
  PACKAGES = Package.group(Snapshot.read(FIXTURE, 'products.jsonl'), log: StringIO.new)
                    .map { |package| package.resolve(Bucket.load(FIXTURE)) }.select(&:available?)
  INDEX_MAPS = IndexMap.build(PACKAGES).to_h { |index_map| [index_map.dataset.slug, index_map] }
  S3 = 'https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation'

  def features(slug)
    JSON.parse(INDEX_MAPS.fetch(slug).geojson)['features']
  end

  def feature(slug, label)
    features(slug).find { |candidate| candidate.dig('properties', 'label') == label }
  end

  def test_each_dem_gets_an_index_map_and_nothing_else_does
    assert_equal %w[dem1 dem13 dem2 s1m], INDEX_MAPS.keys.sort
  end

  def test_an_index_map_outlines_each_tile_and_links_to_its_record_and_cog
    tile = feature('dem13', 'n42w092')
    current = "#{S3}/13/TIFF/current/n42w092/USGS_13_n42w092"

    assert_equal %w[n42w091 n42w092], features('dem13').map { |candidate| candidate.dig('properties', 'label') }
    assert_equal [[[-92, 41], [-91, 41], [-91, 42], [-92, 42], [-92, 41]]], tile.dig('geometry', 'coordinates')
    assert_equal 'usgs-tnm-dem13-n42w092', tile.dig('properties', 'recId')
    assert_equal 'USGS 3DEP 1/3 Arc-Second DEM for 41°–42°N, 91°–92°W (n42w092)', tile.dig('properties', 'title')
    assert_equal "#{current}.tif", tile.dig('properties', 'download')
    assert_equal "#{current}.jpg", tile.dig('properties', 'thumbUrl')
    assert_match(%r{\Ahttps://www\.sciencebase\.gov/catalog/item/}, tile.dig('properties', 'websiteUrl'))
    assert_match(/\A\d{4}\z/, tile.dig('properties', 'datePub'))
    assert tile.dig('properties', 'available')
  end

  # S1M's cells are squares in Albers, so their outlines are tilted against the parallels, and the catalog's box
  # is their envelope
  def test_s1m_cells_are_outlined_in_their_own_grid
    ring = feature('s1m', 'n0450e1510').dig('geometry', 'coordinates').first
    package = PACKAGES.find { |candidate| candidate.id == 'usgs-tnm-s1m-n0450e1510' }
    west, east, north, south = package.bounds
    longitudes, latitudes = ring.transpose

    assert_equal 5, ring.size
    assert_equal ring.first, ring.last
    [[west, longitudes.min], [east, longitudes.max], [north, latitudes.max], [south, latitudes.min]].each do |expected, actual|
      assert_in_delta expected, actual, 1e-5
    end
  end

  # A change to one tile changes one line of the file
  def test_each_outline_is_a_line_of_its_own
    geojson = INDEX_MAPS.fetch('dem13').geojson

    assert_equal features('dem13').size + 2, geojson.lines.size
  end

  def test_an_index_maps_record_points_to_its_geojson
    url = 'https://raw.githubusercontent.com/OpenGeoMetadata/gov.usgs.tnm/main/index-maps/usgs-tnm-index-dem13.geojson'
    record = INDEX_MAPS.fetch('dem13').record(url, 2_000)
    refs = JSON.parse(record['dct_references_s'])

    assert_equal 'usgs-tnm-index-dem13', record['id']
    assert_equal 'Index to USGS 3DEP 1/3 Arc-Second DEM Tiles', record['dct_title_s']
    refute record.key?('dct_description_sm'), 'USGS gives index maps no description, and none is made up'
    assert_equal ['Maps'], record['gbl_resourceClass_sm']
    assert_equal ['Index maps'], record['gbl_resourceType_sm']
    assert_equal 'GeoJSON', record['dct_format_s']
    assert_equal ['usgs-tnm-dem13'], record['pcdm_memberOf_sm']
    assert_equal ['https://creativecommons.org/publicdomain/zero/1.0/'], record['dct_license_sm']
    assert_equal url, refs['https://openindexmaps.org']
    assert_equal [{ 'url' => url, 'label' => 'GeoJSON (2 KB)' }], refs['http://schema.org/downloadUrl']
    assert_equal 'ENVELOPE(-92.00055556, -89.99944444, 42.00055556, 40.99944444)', record['dcat_bbox']
  end
end
