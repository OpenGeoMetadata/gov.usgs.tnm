require 'minitest/autorun'
require 'stringio'
require_relative '../package'

# File names are real ones from The National Map's catalog, chosen for the naming schemes they exercise
class PackageTest < Minitest::Test
  S3 = 'https://prd-tnm.s3.amazonaws.com/StagedProducts'

  def product(tag, url, title: 'Title', published: '2026-02-12', **fields)
    { 'dataset_tag' => tag, 'downloadURL' => url, 'title' => title, 'publicationDate' => published,
      'sourceId' => url, 'boundingBox' => { 'minX' => -96.6, 'maxX' => -90.1, 'minY' => 40.4, 'maxY' => 43.5 } }
      .merge(fields.transform_keys(&:to_s))
  end

  def group(*products)
    Package.group(products, log: StringIO.new)
  end

  # [tag, file URL, product title, expected local id, expected format]
  NAMES = [
    ['National Boundary Dataset (NBD)', "#{S3}/GovtUnit/GPKG/GOVTUNIT_Iowa_State_GPKG.zip", '', 'nbd-ia', :gpkg],
    ['National Boundary Dataset (NBD)', "#{S3}/GovtUnit/National/GDB/GovernmentUnits_National_GDB.zip", '',
     'nbd-national', :gdb],
    ['National Transportation Dataset (NTD)',
     "#{S3}/Tran/Shape/TRAN_United_States_Virgin_Islands_State_Shape.zip", '', 'ntd-vi', :shp],
    ['National Structures Dataset (NSD)',
     "#{S3}/Struct/GDB/STRUCT_Commonwealth_of_the_Northern_Mariana_Islands_State_GDB.zip", '', 'nsd-mp', :gdb],
    ['National Hydrography Dataset (NHD) Best Resolution',
     "#{S3}/Hydrography/NHD/HU8/GPKG/NHD_H_05120101_HU8_GPKG.zip", '', 'nhd-hu8-05120101', :gpkg],
    ['National Hydrography Dataset (NHD) Best Resolution',
     "#{S3}/Hydrography/NHD/State/GDB/NHD_H_District_of_Columbia_State_GDB.zip", '', 'nhd-dc', :gdb],
    ['National Hydrography Dataset Plus High Resolution (NHDPlus HR)',
     "#{S3}/Hydrography/NHDPlusHR/VPU/Current/GDB/NHDPLUS_H_1507_HU4_20220901_GDB.zip", '', 'nhdplushr-hu4-1507', :gdb],
    ['National Hydrography Dataset Plus High Resolution (NHDPlus HR)',
     "#{S3}/Hydrography/NHDPlusHR/VPU/Current/Gpkg/NHDPLUS_H_0418i_HU4_GPKG.zip", '', 'nhdplushr-hu4-0418i', :gpkg],
    ['National Hydrography Dataset Plus High Resolution (NHDPlus HR)',
     "#{S3}/Hydrography/NHDPlusHR/National/GDB/NHDPlus_H_National_Release_2_GDB.zip", '',
     'nhdplushr-national-release-2', :gdb],
    ['National Watershed Boundary Dataset (WBD)', "#{S3}/Hydrography/WBD/HU2/Shape/WBD_07_HU2_Shape.zip", '',
     'wbd-hu2-07', :shp],
    ['3D Hydrography Program (3DHP)',
     "#{S3}/Hydrography/3DHP/Annual/GPKG/3dhp_all_GPKG_FY26_CONUS_20260112/3dhp_all_CONUS_20260112_GPKG.zip", '',
     '3dhp-conus-20260112', :gpkg],
    ['Map Indices', "#{S3}/MapIndices/National/GDB/MapIndices_National_GDB.zip", '', 'mapindices-national', :gdb],
    ['National Geographic Names Information System (GNIS)',
     "#{S3}/GeographicNames/DomesticNames/DomesticNames_IA_Text.zip", '', 'gnis-domesticnames-ia', :txt],
    ['National Geographic Names Information System (GNIS)',
     "#{S3}/GeographicNames/FederalCodes/FedCodes_AllStates_Text.zip", '', 'gnis-fedcodes-allstates', :txt],
    ['National Geographic Names Information System (GNIS)',
     "#{S3}/GeographicNames/Antarctica/Gazetteer_Antarctica_GPKG.zip", '', 'gnis-fullmodel-antarctica', :gpkg],
    ['National Geographic Names Information System (GNIS)',
     "#{S3}/GeographicNames/Topical/PopulatedPlaces_National_Text.zip", '', 'gnis-populatedplaces-national', :txt],
    ['National Geographic Names Information System (GNIS)', 'https://geonames.usgs.gov/docs/stategaz/VT_Features.zip',
     '', 'gnis-gazetteer-vt', :txt],
    ['Small-scale Datasets - Boundaries', "#{S3}/Small-scale/data/Boundaries/countyl010g_shp_nt00964.tar.gz", '',
     'smallscale-countyl010g', :shp],
    ['Small-scale Datasets - Boundaries', "#{S3}/Small-scale/data/Boundaries/coastl_usa.gdb_nt00910.tar.gz", '',
     'smallscale-coastl-usa', :gdb],
    ['National Elevation Dataset (NED) 1/3 arc-second - Contours',
     "#{S3}/Contours/GPKG/ELEV_Aberdeen_E_SD_1X1_GPKG.zip", '', 'contours-sd-aberdeen-e', :gpkg],
    ['National Elevation Dataset (NED) 1/3 arc-second - Contours',
     "#{S3}/Contours/Shape/ELEV_Montreal_E_QC1X1_Shape.zip", '', 'contours-qc-montreal-e', :shp],
    ['National Elevation Dataset (NED) 1/3 arc-second - Contours', "#{S3}/Contours/Shape/Elev_321263_Brandon_W_1X1.zip",
     'USGS Contours for Brandon W, Manitoba 20121105 1 x 1 degree Shapefile', 'contours-mb-brandon-w-321263', :shp],
    ['Combined Vector', "#{S3}/TopoMapVector/DC/GPKG/VECTOR_Washington_West_DC_7_5_Min_GPKG.zip",
     'USGS Topo Map Vector Data (Vector) 47611 Washington West DC (published 20250730) GeoPackage', 'vector-47611', :gpkg],
    ['Combined Vector', "#{S3}/Vector/FileGDB101/VECTOR_321168_Albany_E_1X1.zip", '', 'vector-1x1-321168', :gdb]
  ].freeze

  def test_file_names_say_what_area_each_file_covers_and_its_format
    NAMES.each do |tag, url, title, local_id, format|
      dataset = Datasets.for_tag(tag)
      unit, parsed_format = Package.parse(dataset, url, product(tag, url, title: title))

      assert_equal local_id, Package.local_id(dataset, unit), url
      assert_equal format, parsed_format, url
    end
  end

  def test_formats_of_an_area_are_one_package
    tag = 'National Boundary Dataset (NBD)'
    packages = group(*%w[GPKG GDB Shape].map { |suffix| product(tag, "#{S3}/GovtUnit/#{suffix}/GOVTUNIT_Iowa_State_#{suffix}.zip") })

    assert_equal 1, packages.size
    assert_equal 'usgs-tnm-nbd-ia', packages.first.id
  end

  # 3DHP's FY25 and FY26 editions are both available
  def test_editions_of_3dhp_are_packages_of_their_own
    tag = '3D Hydrography Program (3DHP)'
    packages = group(product(tag, "#{S3}/Hydrography/3DHP/Annual/GDB/x/3dhp_all_CONUS_20250313_GDB.zip"),
                     product(tag, "#{S3}/Hydrography/3DHP/Annual/GDB/x/3dhp_all_CONUS_20260112_GDB.zip"))

    assert_equal %w[usgs-tnm-3dhp-conus-20250313 usgs-tnm-3dhp-conus-20260112], packages.map(&:id).sort
  end

  # A subregion's GeoPackage can be named with its edition's date and its geodatabase without
  def test_a_hydrologic_units_files_are_one_package_whatever_their_dates
    tag = 'National Hydrography Dataset Plus High Resolution (NHDPlus HR)'
    base = "#{S3}/Hydrography/NHDPlusHR/VPU/Current"
    packages = group(product(tag, "#{base}/GDB/NHDPLUS_H_1507_HU4_GDB.zip"),
                     product(tag, "#{base}/GPKG/NHDPLUS_H_1507_HU4_20220901_GPKG.zip",
                             urls: { 'GeoTIFF' => "#{base}/Raster/NHDPLUS_H_1507_HU4_20220901_RASTER.zip" }))
    bucket = Bucket.new({})

    assert_equal 1, packages.size
    files = packages.first.instance_variable_get(:@files)
    assert_equal %i[gdb gpkg raster], files.keys.sort
    refute packages.first.resolve(bucket).available?, 'nothing is on the empty bucket'
  end

  # The same file is sometimes listed as two products
  def test_a_file_listed_twice_is_one_download
    tag = 'Small-scale Datasets - Contours'
    url = "#{S3}/Small-scale/data/Contours/conthil010a.gdb_nt00943.tar.gz"
    packages = group(product(tag, url), product(tag, url, sourceId: 'another'))
    bucket = Bucket.new({ Bucket.key(url) => 1_234 })

    assert_equal 1, packages.first.resolve(bucket).downloads.size
  end

  # Should one format be listed twice, the file published last is kept
  def test_the_latest_file_of_a_format_is_kept
    tag = 'National Hydrography Dataset Plus High Resolution (NHDPlus HR)'
    base = "#{S3}/Hydrography/NHDPlusHR/VPU/Current/GDB"
    old = product(tag, "#{base}/NHDPLUS_H_1507_HU4_20180101_GDB.zip", published: '2018-01-01')
    new = product(tag, "#{base}/NHDPLUS_H_1507_HU4_20220901_GDB.zip", published: '2022-09-01')
    [[old, new], [new, old]].each do |products|
      bucket = Bucket.new({ Bucket.key(old['downloadURL']) => 1, Bucket.key(new['downloadURL']) => 2 })
      package = group(*products).first.resolve(bucket)

      assert_equal [new['downloadURL']], package.downloads.map(&:url)
    end
  end

  def test_files_missing_from_the_bucket_are_dropped_and_the_rest_measured
    tag = 'National Boundary Dataset (NBD)'
    gpkg, gdb = %w[GPKG GDB].map { |suffix| "#{S3}/GovtUnit/#{suffix}/GOVTUNIT_Iowa_State_#{suffix}.zip" }
    jpg = gdb.sub('.zip', '.jpg')
    xml = gdb.sub('.zip', '.xml')
    bucket = Bucket.new({ Bucket.key(gdb) => 23_600_000, Bucket.key(jpg) => 1, Bucket.key(xml) => 1 })
    package = group(product(tag, gpkg), product(tag, gdb)).first.resolve(bucket)

    assert_equal [[gdb, :gdb, 23_600_000]], package.downloads.map { |download| [download.url, download.format, download.size] }
    assert_equal jpg, package.thumbnail_url
    assert_equal xml, package.metadata_url
  end

  # GNIS's 2017 files aren't on the bucket, so they're checked one by one and can't be measured unless the server says
  def test_files_elsewhere_are_available_unless_found_missing
    tag = 'National Geographic Names Information System (GNIS)'
    url = 'https://geonames.usgs.gov/docs/stategaz/VT_Features.zip'
    package = group(product(tag, url, vendorMetaUrl: 'https://example.com/vt.xml')).first

    assert package.resolve(Bucket.new({}, { url => [true, 5_000] })).available?
    refute package.resolve(Bucket.new({}, { url => [false, nil] })).available?
    assert_equal 'https://example.com/vt.xml', package.metadata_url
  end

  # Summaries are wrapped and indented as the metadata they were copied from, and the odd one is HTML
  def test_summaries_are_read_as_paragraphs
    assert_equal ['These vector contour lines were created to support topographic map products.'],
                 Package.paragraphs("These vector contour lines were\n\t\t\t\tcreated to support topographic map products.")
    assert_equal ['NR2 is an update to NR1.', 'Only vector data is included—none of the raster data.', 'An update.'],
                 Package.paragraphs("<div>NR2 is an update to NR1.<br>\n<br>\nOnly vector data is included&#8212;none " \
                                    "of the raster data.&nbsp;<br>\n</div>\n\n<div><br>\nAn update.</div>\n")
    assert_empty Package.paragraphs(nil)
  end

  def test_unrecognized_names_still_make_packages_and_are_reported
    log = StringIO.new
    packages = Package.group([product('Map Indices', "#{S3}/MapIndices/GDB/SomethingNew_GDB.zip")], log: log)

    assert_equal 'usgs-tnm-mapindices-somethingnew-gdb', packages.first.id
    assert_match(/1 mapindices files have names the harvester doesn't recognize/, log.string)
  end
end
