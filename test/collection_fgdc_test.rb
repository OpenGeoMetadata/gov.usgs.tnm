require 'minitest/autorun'
require 'json'
require 'stringio'
require 'tmpdir'
require_relative '../collection_fgdc'
require_relative '../index_map'

class CollectionFgdcTest < Minitest::Test
  # Answers like ScienceBase's item API, from each item's files
  class FakeScienceBase
    Response = Struct.new(:code, :body) do
      def is_a?(type)
        type == Net::HTTPSuccess ? code == '200' : super
      end
    end

    attr_reader :requests

    # @param items [Hash{String => Array, Integer}] each item's files, or the status it answers with
    def initialize(items)
      @items = items
      @requests = []
    end

    def get(url)
      @requests << url
      item = url[%r{/catalog/item/(\w+)\?format=json\z}, 1]
      files = @items.fetch(item, 404)
      files.is_a?(Integer) ? Response.new(files.to_s, '') : Response.new('200', JSON.generate('id' => item, 'files' => files))
    end
  end

  FGDC = 'https://www.sciencebase.gov/catalog/file/get/4f70aa9fe4b058caae3f8de5?f=__disk__e4%2F8a%2F44'

  def fetch(items, sciencebase)
    CollectionFgdc.fetch(items, http: sciencebase, log: StringIO.new)
  end

  def test_takes_the_fgdc_file_from_each_models_collection_item
    sciencebase = FakeScienceBase.new(
      'item13' => [{ 'name' => 'preview.png', 'contentType' => 'image/png', 'url' => 'https://example.com/preview.png' },
                   { 'name' => 'USGS_3DEP_13_Collection.xml', 'contentType' => 'application/fgdc+xml', 'url' => FGDC }]
    )

    fgdc = fetch({ 'dem13' => 'item13' }, sciencebase)

    assert_equal FGDC, fgdc.url('dem13')
    assert_equal ['https://www.sciencebase.gov/catalog/item/item13?format=json'], sciencebase.requests
  end

  # A record is complete without it, so the run goes on: Small-scale Datasets' item holds none
  def test_a_dataset_whose_item_holds_no_fgdc_gets_no_link
    fgdc = fetch({ 'dem13' => 'item13' }, FakeScienceBase.new('item13' => []))

    assert_nil fgdc.url('dem13')
  end

  # ...but a ScienceBase that can't be read is not the same as an FGDC that isn't there, and a link taken away
  # for one bad day would come back the next
  def test_an_item_that_cannot_be_read_stops_the_run
    error = assert_raises(CollectionFgdc::Error) { fetch({ 'dem13' => 'item13' }, FakeScienceBase.new('item13' => 503)) }

    assert_match 'item13', error.message
  end

  # Its landing page, for most datasets
  def test_takes_a_datasets_collection_item_from_its_landing_page
    assert_equal '4f70b219e4b058caae3f8e19', CollectionFgdc.items.fetch('nbd')
  end

  # A dataset whose landing page is a USGS program page has its item named: Contours' is 3DEP's
  def test_takes_a_named_collection_item_for_a_dataset_whose_landing_page_is_elsewhere
    assert_equal '4f70ab22e4b058caae3f8deb', CollectionFgdc.items.fetch('contours')
  end

  def test_knows_the_collection_item_of_every_dataset
    Datasets::ALL.each { |dataset| assert CollectionFgdc.items.key?(dataset.slug), "no collection item for #{dataset.slug}" }
  end

  def test_looks_up_nothing_for_a_dataset_with_no_known_item
    elsewhere = Datasets.fetch('contours').with(slug: 'elsewhere')

    assert_empty CollectionFgdc.items([elsewhere])
  end

  def test_keeps_what_it_found_in_the_snapshot
    Dir.mktmpdir do |dir|
      fetch({ 'dem13' => 'item13' }, FakeScienceBase.new('item13' => [{ 'contentType' => 'application/fgdc+xml', 'url' => FGDC }])).save(dir)

      assert_equal FGDC, CollectionFgdc.load(dir).url('dem13')
    end
  end
end
