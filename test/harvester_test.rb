require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require_relative '../harvester'

# The fixture is a real snapshot, cut down to a few packages of each dataset: see test/fixtures/README.md
class HarvesterTest < Minitest::Test
  FIXTURE = File.join(__dir__, 'fixtures', 'snapshot')
  PRODUCTS = Snapshot.read(FIXTURE, 'products.jsonl')
  OBJECTS = Snapshot.read(FIXTURE, 'bucket.jsonl')
  REMOTE = Snapshot.read(FIXTURE, 'remote.jsonl')
  TODAY = Date.new(2026, 10, 2)

  # Three of the fixture's packages are gone from the download server: Brandon W's contours and Albany E's
  # 1 x 1 degree vector data, which the bucket no longer has, and Iowa's 2017 GNIS file, which geonames.usgs.gov
  # now redirects to a web page. The rest each make a record.
  PACKAGES = Package.group(PRODUCTS, log: StringIO.new).map { |package| package.resolve(Bucket.load(FIXTURE)) }
  RECORDS = PACKAGES.count(&:available?)
  UNAVAILABLE = %w[usgs-tnm-contours-mb-brandon-w-321263 usgs-tnm-vector-1x1-321168 usgs-tnm-gnis-gazetteer-ia].freeze
  COLLECTIONS = Datasets::ALL.size

  def setup
    @tmp_dir = Dir.mktmpdir
    @metadata_dir = File.join(@tmp_dir, 'metadata-aardvark')
    @withdrawn_file = File.join(@tmp_dir, 'withdrawn.json')
    @sources = 0
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
  end

  # A snapshot directory holding the given products, bucket listing and checks of files elsewhere
  def snapshot(products = PRODUCTS, objects = OBJECTS, remote = REMOTE)
    dir = File.join(@tmp_dir, "snapshot-#{@sources += 1}")
    FileUtils.mkdir_p(dir)
    { 'products.jsonl' => products, 'bucket.jsonl' => objects, 'remote.jsonl' => remote }.each do |name, rows|
      File.write(File.join(dir, name), rows.map { |row| "#{JSON.generate(row)}\n" }.join)
    end
    dir
  end

  def harvest(source, **options)
    Harvester.run(source: source, metadata_dir: @metadata_dir, withdrawn_file: @withdrawn_file, today: TODAY,
                  log: StringIO.new, **options)
  end

  def record_path(id)
    File.join(@metadata_dir, *Harvester.directories(id), "#{id}.json")
  end

  def record(id)
    JSON.parse(File.read(record_path(id)))
  end

  def withdrawals
    JSON.parse(File.read(@withdrawn_file))['withdrawn']
  end

  # The products without the files whose URLs include `fragment`
  def without(fragment)
    PRODUCTS.reject { |product| product['downloadURL'].include?(fragment) }
  end

  def test_writes_a_record_per_package_in_its_datasets_directory
    counts = harvest(snapshot)

    assert_equal RECORDS, counts[:created]
    {
      'usgs-tnm-nbd-ia' => 'nbd',
      'usgs-tnm-nhd-hu8-05120101' => 'nhd/05',
      'usgs-tnm-nhd-dc' => 'nhd',
      'usgs-tnm-contours-sd-aberdeen-e' => 'contours/sd',
      'usgs-tnm-vector-47611' => 'vector/47',
      'usgs-tnm-gnis-fullmodel-ia' => 'gnis'
    }.each do |id, directory|
      assert File.exist?(File.join(@metadata_dir, directory, "#{id}.json")), "#{id} should be in #{directory}"
    end
    refute File.exist?(@withdrawn_file), 'nothing was withdrawn, so there should be no log'
  end

  def test_packages_with_no_files_left_get_no_record
    counts = harvest(snapshot)

    assert_equal UNAVAILABLE.size, counts[:unavailable]
    UNAVAILABLE.each { |id| refute File.exist?(record_path(id)), id }
  end

  def test_writes_a_collection_record_for_each_dataset
    counts = harvest(snapshot)

    assert_equal COLLECTIONS, counts[:collections_created]
    collection = JSON.parse(File.read(File.join(@metadata_dir, 'nbd', 'usgs-tnm-nbd.json')))
    assert_equal ['Collections'], collection['gbl_resourceClass_sm']
    assert_equal ['usgs-tnm-nbd'], record('usgs-tnm-nbd-ia')['pcdm_memberOf_sm']
  end

  def test_files_are_pretty_printed_utf8_with_a_trailing_newline
    harvest(snapshot)
    content = File.read(record_path('usgs-tnm-nbd-ia'), mode: 'r:utf-8')

    assert content.start_with?("{\n  \"id\": \"usgs-tnm-nbd-ia\",")
    assert content.end_with?("}\n")
  end

  def test_second_run_changes_nothing
    source = snapshot
    harvest(source)
    counts = harvest(source)

    assert_equal 0, counts[:created]
    assert_equal 0, counts[:updated]
    assert_equal RECORDS, counts[:unchanged]
    assert_equal COLLECTIONS, counts[:collections_unchanged]
  end

  def test_changed_product_updates_its_record
    harvest(snapshot)
    products = PRODUCTS.map do |product|
      product['downloadURL'].include?('GOVTUNIT_Iowa_State_') ? product.merge('publicationDate' => '2026-09-30') : product
    end
    counts = harvest(snapshot(products))

    assert_equal 1, counts[:updated]
    assert_equal '2026-09-30', record('usgs-tnm-nbd-ia')['dct_issued_s']
  end

  def test_withdraws_packages_that_leave_the_catalog
    harvest(snapshot)
    counts = harvest(snapshot(without('GOVTUNIT_Iowa_State_')), max_shrink: 1.0)

    assert_equal 1, counts[:withdrawn]
    refute File.exist?(record_path('usgs-tnm-nbd-ia'))
    log = JSON.parse(File.read(@withdrawn_file))
    assert_equal 'https://opengeometadata.org/schema/ogm-withdrawals-1.0.json', log['$schema']
    assert_equal [{ 'id' => 'usgs-tnm-nbd-ia', 'date' => '2026-10-02', 'reason' => 'upstream-removed' }],
                 log['withdrawn']
  end

  def test_package_whose_files_are_gone_is_withdrawn_for_quality
    harvest(snapshot)
    objects = OBJECTS.reject { |key, _size| key.include?('GOVTUNIT_Iowa_State_') && key.end_with?('.zip') }
    counts = harvest(snapshot(PRODUCTS, objects), max_shrink: 1.0)

    assert_equal 1, counts[:without_files]
    assert_equal 'quality', withdrawals.first['reason']
  end

  def test_files_missing_from_the_bucket_are_left_out_of_a_record
    objects = OBJECTS.reject { |key, _size| key.end_with?('GOVTUNIT_Iowa_State_Shape.zip') }
    harvest(snapshot(PRODUCTS, objects))
    downloads = JSON.parse(record('usgs-tnm-nbd-ia')['dct_references_s'])['http://schema.org/downloadUrl']

    assert_equal ['GeoPackage', 'File geodatabase'], (downloads.map { |download| download['label'][/\A[^(]+/].strip })
  end

  # 3DHP's FY25 edition stays available beside FY26's; when it goes, FY26's record replaces it
  def test_an_earlier_3dhp_edition_is_superseded_by_a_later_one
    harvest(snapshot)
    counts = harvest(snapshot(without('3dhp_all_CONUS_20250313')), max_shrink: 1.0)

    assert_equal 1, counts[:superseded]
    entry = withdrawals.first
    assert_equal 'usgs-tnm-3dhp-conus-20250313', entry['id']
    assert_equal ['usgs-tnm-3dhp-conus-20260112'], entry['is_replaced_by']
  end

  def test_republished_package_leaves_the_log
    harvest(snapshot)
    harvest(snapshot(without('GOVTUNIT_Iowa_State_')), max_shrink: 1.0)
    counts = harvest(snapshot, max_shrink: 1.0)

    assert_equal 1, counts[:republished]
    assert_empty withdrawals
    assert record('usgs-tnm-nbd-ia')
  end

  # The only quadrangle in its bucket leaves an empty directory, which goes with it
  def test_emptied_directories_are_removed
    harvest(snapshot)
    harvest(snapshot(without('VECTOR_Washington_West_DC_7_5_Min_')), max_shrink: 1.0)

    refute Dir.exist?(File.join(@metadata_dir, 'vector', '47'))
    assert Dir.exist?(File.join(@metadata_dir, 'vector'))
  end

  def test_refuses_to_withdraw_after_a_large_drop
    harvest(snapshot)
    error = assert_raises(Harvester::Error) { harvest(snapshot(without('GOVTUNIT_Iowa_State_'))) }

    assert_match(/down from #{RECORDS}/, error.message)
    assert record('usgs-tnm-nbd-ia'), 'no records should be removed'
    refute File.exist?(@withdrawn_file)
  end

  def test_force_allows_a_large_drop
    harvest(snapshot)
    counts = harvest(snapshot(without('GOVTUNIT_Iowa_State_')), force: true)

    assert_equal 1, counts[:withdrawn]
  end

  # A catalog with nothing for a dataset is a broken catalog, not a withdrawn dataset
  def test_refuses_a_catalog_missing_a_dataset
    woodland = Datasets.fetch('woodland').tags
    products = PRODUCTS.reject { |product| woodland.include?(product['dataset_tag']) }
    error = assert_raises(Harvester::Error) { harvest(snapshot(products)) }

    assert_match(/lists nothing for USGS Woodland Tint/, error.message)
    refute Dir.exist?(@metadata_dir)
  end

  def test_titles_a_dataset_shares_get_their_publication_dates
    contours = PRODUCTS.select { |product| product['downloadURL'].include?('ELEV_Aberdeen_E_SD_1X1_') }
    namesake = contours.map do |product|
      product.merge('downloadURL' => product['downloadURL'].sub('Aberdeen_E_SD', 'Aberdeen_E_ND'),
                    'publicationDate' => '2020-01-01')
    end
    objects = OBJECTS + OBJECTS.select { |key, _size| key.include?('ELEV_Aberdeen_E_SD_1X1_') }
                               .map { |key, size| [key.sub('Aberdeen_E_SD', 'Aberdeen_E_ND'), size] }
    harvest(snapshot(PRODUCTS + namesake, objects))

    assert_match(/\(1 x 1 Degree\) \(published \d{4}-\d{2}-\d{2}\)\z/, record('usgs-tnm-contours-sd-aberdeen-e')['dct_title_s'])
    assert_match(/\(published 2020-01-01\)\z/, record('usgs-tnm-contours-nd-aberdeen-e')['dct_title_s'])
  end

  def test_dry_run_writes_nothing
    counts = harvest(snapshot, dry_run: true)

    assert_equal RECORDS, counts[:created]
    refute Dir.exist?(@metadata_dir)
  end
end
