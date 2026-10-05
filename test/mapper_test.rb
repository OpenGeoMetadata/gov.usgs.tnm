require 'minitest/autorun'
require 'json'
require 'stringio'
require_relative '../mapper'

# Records for real packages, from the fixture snapshot: see test/fixtures/README.md
class MapperTest < Minitest::Test
  FIXTURE = File.join(__dir__, 'fixtures', 'snapshot')
  PACKAGES = Package.group(Snapshot.read(FIXTURE, 'products.jsonl'), log: StringIO.new)
                    .map { |package| package.resolve(Bucket.load(FIXTURE)) }.to_h { |package| [package.id, package] }
  S3 = 'https://prd-tnm.s3.amazonaws.com/StagedProducts'

  def map(id, **options)
    Mapper.map(PACKAGES.fetch(id), **options)
  end

  def references(id)
    JSON.parse(map(id)['dct_references_s'])
  end

  def labels(id)
    references(id)['http://schema.org/downloadUrl'].map { |download| download['label'] }
  end

  def test_iowa_boundaries_record
    record = map('usgs-tnm-nbd-ia')

    assert_equal 'USGS National Boundary Dataset (NBD) for Iowa', record['dct_title_s']
    assert_equal ['Geospatial data is comprised of government boundaries.'], record['dct_description_sm']
    assert_equal ['Geological Survey (U.S.)'], record['dct_creator_sm']
    assert_equal '2026-02-12', record['dct_issued_s']
    assert_equal [2026], record['gbl_indexYear_im']
    assert_equal ['Iowa'], record['dct_spatial_sm']
    assert_equal 3, record['dct_identifier_sm'].size
    assert_equal ['Polygon data', 'Line data'], record['gbl_resourceType_sm']
    assert_equal ['Boundaries'], record['dcat_theme_sm']
    assert_equal ['The National Map', 'National Boundary Dataset', 'State'], record['dcat_keyword_sm']
    assert_equal 'GeoPackage', record['dct_format_s']
    assert_equal 'ENVELOPE(-96.63949, -90.14006, 43.5012, 40.37544)', record['dcat_bbox']
    assert_equal '41.93832,-93.389775', record['dcat_centroid']
    assert_equal ['usgs-tnm-nbd'], record['pcdm_memberOf_sm']
    assert_equal '2026-02-14T03:21:25Z', record['gbl_mdModified_dt']
    refute record.key?('dct_relation_sm')
  end

  # A package's description is the summary USGS gives its products, however short, with the line breaks of the
  # metadata it was copied from undone and nothing added
  def test_descriptions_are_usgs_summaries
    description = map('usgs-tnm-contours-sd-aberdeen-e')['dct_description_sm']

    assert_equal 1, description.size
    assert_match(/\AThese vector contour lines .+\. They were created to support 1:24,000-scale CONUS/, description.first)
    refute_match(/\s{2}|\n/, description.first)
  end

  def test_iowa_boundaries_references
    refs = references('usgs-tnm-nbd-ia')
    base = "#{S3}/GovtUnit"

    assert_equal 'https://carto.nationalmap.gov/arcgis/rest/services/govunits/MapServer',
                 refs['urn:x-esri:serviceType:ArcGIS#DynamicMapLayer']
    assert_equal [
      { 'url' => "#{base}/GPKG/GOVTUNIT_Iowa_State_GPKG.zip", 'label' => 'GeoPackage (48.3 MB)' },
      { 'url' => "#{base}/GDB/GOVTUNIT_Iowa_State_GDB.zip", 'label' => 'File geodatabase (27.5 MB)' },
      { 'url' => "#{base}/Shape/GOVTUNIT_Iowa_State_Shape.zip", 'label' => 'Shapefile (45.4 MB)' }
    ], refs['http://schema.org/downloadUrl']
    assert_equal "#{base}/GPKG/GOVTUNIT_Iowa_State_GPKG.xml", refs['http://www.opengis.net/cat/csw/csdgm']
    assert_equal 'https://www.sciencebase.gov/catalog/item/62f73597d34eacf539747d47', refs['http://schema.org/url']
    assert_equal "#{base}/GPKG/GOVTUNIT_Iowa_State_GPKG.jpg", refs['http://schema.org/thumbnailUrl']
    assert_equal 'urn:x-esri:serviceType:ArcGIS#DynamicMapLayer', refs.keys.first, 'services come first'
  end

  def test_hydrologic_units_are_named
    assert_equal 'USGS National Hydrography Dataset (NHD) for the Upper Wabash Subbasin (HU-8 05120101)',
                 map('usgs-tnm-nhd-hu8-05120101')['dct_title_s']
    assert_equal 'USGS Watershed Boundary Dataset (WBD) for the New England Region (HU-2 01)',
                 map('usgs-tnm-wbd-hu2-01')['dct_title_s']
    assert_equal 'USGS NHDPlus High Resolution (NHDPlus HR) for the Connecticut Subregion (HU-4 0108)',
                 map('usgs-tnm-nhdplushr-hu4-0108')['dct_title_s']
  end

  # Hydrologic units cross state lines, so they name no places
  def test_hydrologic_units_have_no_places
    record = map('usgs-tnm-nhd-hu8-05120101')

    refute record.key?('dct_spatial_sm')
    assert_equal ['The National Map', 'National Hydrography Dataset', 'HU-8 Subbasin'], record['dcat_keyword_sm']
  end

  # The cached hydrography tiles are a basemap of the whole world, not NHD, so only NHD's own service draws it
  def test_hydrography_records_have_only_their_own_service
    refs = references('usgs-tnm-nhd-hu8-05120101')

    assert_equal ['urn:x-esri:serviceType:ArcGIS#DynamicMapLayer'], refs.keys.grep(/esri/)
    assert_equal 'https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer',
                 refs['urn:x-esri:serviceType:ArcGIS#DynamicMapLayer']
  end

  def test_nhdplus_rasters_are_a_download_of_their_own
    assert_equal ['GeoPackage (456.7 MB)', 'File geodatabase (212.0 MB)', 'Rasters (GeoTIFF) (2.8 GB)'],
                 labels('usgs-tnm-nhdplushr-hu4-0108')
  end

  def test_quadrangles_have_no_services
    record = map('usgs-tnm-vector-47611')
    refs = JSON.parse(record['dct_references_s'])

    assert_equal 'USGS Topo Map Vector Data for Washington West, DC', record['dct_title_s']
    assert_equal ['District of Columbia'], record['dct_spatial_sm']
    assert_empty refs.keys.grep(/esri/)
    assert_equal ['GeoPackage (14.3 MB)', 'File geodatabase (7.1 MB)', 'Shapefile (12.8 MB)'], labels('usgs-tnm-vector-47611')
  end

  # Both of 3DHP's CONUS editions are available, and named for their fiscal years
  def test_3dhp_editions_are_named_for_their_fiscal_years
    assert_equal 'USGS 3D Hydrography Program (3DHP) for the Conterminous United States (FY25)',
                 map('usgs-tnm-3dhp-conus-20250313')['dct_title_s']
    assert_equal 'USGS 3D Hydrography Program (3DHP) for the Conterminous United States (FY26)',
                 map('usgs-tnm-3dhp-conus-20260112')['dct_title_s']
    assert_equal ['United States'], map('usgs-tnm-3dhp-conus-20260112')['dct_spatial_sm']
  end

  def test_gnis_files_are_named_for_what_they_hold
    assert_equal 'USGS Geographic Names Information System (GNIS) Domestic Names for Iowa',
                 map('usgs-tnm-gnis-domesticnames-ia')['dct_title_s']
    assert_equal 'USGS Geographic Names Information System (GNIS) Full Model for Iowa',
                 map('usgs-tnm-gnis-fullmodel-ia')['dct_title_s']
    assert_equal 'USGS Geographic Names Information System (GNIS) All Names for the United States',
                 map('usgs-tnm-gnis-allnames-national')['dct_title_s']
    assert_equal 'Tabular Data', map('usgs-tnm-gnis-domesticnames-ia')['dct_format_s']
  end

  # Small-scale datasets have no metadata beside their files, so the catalog's copy is linked instead
  def test_small_scale_datasets_go_by_usgs_names_for_them
    record = map('usgs-tnm-smallscale-statesp010g')
    refs = JSON.parse(record['dct_references_s'])

    assert_equal 'USGS 1:1,000,000-Scale State Boundaries of the United States', record['dct_title_s']
    assert_equal ['Boundaries'], record['dcat_theme_sm']
    assert_equal 'Geodatabase', record['dct_format_s']
    assert_equal 'https://thor-f5.er.usgs.gov/ngtoc/metadata/waf/small-scale/filegdb101/statesp010g_gdb.xml',
                 refs['http://www.opengis.net/cat/csw/csdgm']
    assert_empty refs.keys.grep(/esri/), 'small-scale datasets have no service'
  end

  # The tile's title writes its province against "1 x 1 degree", and its file name its code against "1X1"
  def test_contour_tiles_are_named_for_their_place
    record = map('usgs-tnm-contours-qc-montreal-e')

    assert_equal 'USGS 1/3 Arc-Second Contours for Montreal E, Quebec (1 x 1 Degree)', record['dct_title_s']
    assert_equal ['Quebec'], record['dct_spatial_sm']
    assert_equal ['The National Map', 'Contours', '1 x 1 degree'], record['dcat_keyword_sm']
  end

  def test_a_title_shared_within_a_dataset_gets_the_publication_date
    assert_equal 'USGS National Boundary Dataset (NBD) for Iowa (published 2026-02-12)',
                 map('usgs-tnm-nbd-ia', distinguish: true)['dct_title_s']
  end

  def test_collection_record_summarizes_its_packages
    packages = PACKAGES.values.select { |package| package.dataset.slug == 'nbd' }
    record = Mapper.collection(Datasets.fetch('nbd'), packages)
    refs = JSON.parse(record['dct_references_s'])

    assert_equal 'usgs-tnm-nbd', record['id']
    assert_equal 'USGS National Boundary Dataset (NBD)', record['dct_title_s']
    assert_equal ['Collections'], record['gbl_resourceClass_sm']
    assert_equal Datasets.fetch('nbd').description, record['dct_description_sm']
    assert_equal 'https://carto.nationalmap.gov/arcgis/rest/services/govunits/MapServer',
                 refs['urn:x-esri:serviceType:ArcGIS#DynamicMapLayer']
    assert_equal 'https://www.sciencebase.gov/catalog/item/4f70b219e4b058caae3f8e19', refs['http://schema.org/url']
    refute record.key?('pcdm_memberOf_sm')
  end

  # The National Map describes NHD only as what 3DHP replaces, so its collection takes its packages' summary
  def test_a_collection_without_a_description_of_its_own_takes_its_packages
    packages = PACKAGES.values.select { |package| package.dataset.slug == 'nhd' }
    record = Mapper.collection(Datasets.fetch('nhd'), packages)

    assert_nil Datasets.fetch('nhd').description
    assert_equal packages.first.descriptions, record['dct_description_sm']
    assert_match(/\AThe National Hydrography Dataset \(NHD\) is a feature-based database/, record['dct_description_sm'].first)
  end

  def test_a_collection_takes_the_summary_most_of_its_packages_share
    package = Data.define(:descriptions)
    packages = [package.new(['B']), package.new(['A']), package.new(['B']), package.new([])]

    assert_equal ['B'], Mapper.shared_description(packages)
    assert_equal ['A'], Mapper.shared_description(packages.first(2)), 'ties go to the first alphabetically'
    assert_nil Mapper.shared_description([package.new([])])
  end

  # Alaska's box crosses the antimeridian, so its center is in the western Aleutians' half of the way round
  def test_a_box_crossing_the_antimeridian_is_centered_across_it
    package = Package.group(Snapshot.read(FIXTURE, 'products.jsonl'), log: StringIO.new)
                     .find { |candidate| candidate.id == 'usgs-tnm-nbd-national' }.resolve(Bucket.load(FIXTURE))
    package.bounds = [172.0, -130.0, 71.0, 51.0]
    record = Mapper.map(package)

    assert_equal 'ENVELOPE(172, -130, 71, 51)', record['dcat_bbox']
    assert_equal '61,-159', record['dcat_centroid']
  end

  def test_sizes_are_labelled_in_kilobytes_megabytes_or_gigabytes
    assert_equal '3 KB', Mapper.size_label(2_100)
    assert_equal '48.3 MB', Mapper.size_label(48_300_000)
    assert_equal '22.4 GB', Mapper.size_label(22_378_100_000)
  end
end
