require 'minitest/autorun'
require 'json'
require 'stringio'
require 'uri'
require_relative '../catalog'

class CatalogTest < Minitest::Test
  # Answers like the TNM Access API from a list of products, or with a canned body
  class FakeApi
    Response = Struct.new(:code, :body) do
      def is_a?(type)
        type == Net::HTTPSuccess ? code == '200' : super
      end
    end

    attr_reader :requests

    # @param products [Hash{String => Array}] each query's products, by its value of `key`
    def initialize(products, key: 'datasets', total: nil, body: nil)
      @products = products
      @key = key
      @total = total
      @body = body
      @requests = []
    end

    def get(url)
      params = URI.decode_www_form(URI(url).query).to_h
      @requests << params
      return Response.new('200', @body) if @body

      all = @products.fetch(params[@key] || params['datasets'], [])
      offset = params['offset'].to_i
      page = all[offset, params['max'].to_i] || []
      Response.new('200', JSON.generate('total' => @total || all.size, 'items' => page))
    end
  end

  def products(count, prefix = 'p')
    Array.new(count) { |index| { 'sourceId' => "#{prefix}#{index}", 'title' => "Product #{index}", 'extra' => 'dropped' } }
  end

  def dataset(slug)
    Datasets.fetch(slug)
  end

  def test_pages_through_a_dataset_and_keeps_only_its_fields
    api = FakeApi.new({ 'Map Indices' => products(2500) })
    catalog = Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new)

    assert_equal 2500, catalog.products.size
    assert_equal [0, 1000, 2000], (api.requests.map { |params| params['offset'].to_i })
    assert_equal({ 'title' => 'Product 0', 'sourceId' => 'p0', 'dataset_tag' => 'Map Indices' }, catalog.products.first)
  end

  # Combined Vector has more products than one query can page through, so it's fetched a format at a time
  def test_fetches_a_big_dataset_in_parts
    parts = { 'FileGDB' => products(3, 'g'), 'FileGDB 10.1' => [], 'Shapefile' => products(3, 's'),
              'GeoPackage' => products(2, 'k') }
    api = FakeApi.new(parts, key: 'prodFormats', total: nil)
    def api.get(url)
      params = URI.decode_www_form(URI(url).query).to_h
      return super if params['prodFormats']

      @requests << params
      FakeApi::Response.new('200', JSON.generate('total' => 8, 'items' => []))
    end
    catalog = Catalog.fetch([dataset('vector')], http: api, log: StringIO.new)

    assert_equal 8, catalog.products.size
    assert_equal ['FileGDB', 'FileGDB 10.1', 'Shapefile', 'GeoPackage', nil],
                 (api.requests.map { |params| params['prodFormats'] }.uniq)
  end

  def test_parts_that_miss_products_stop_the_run
    api = FakeApi.new({ 'Shapefile' => products(3) }, key: 'prodFormats')
    def api.get(url)
      params = URI.decode_www_form(URI(url).query).to_h
      return super if params['prodFormats']

      FakeApi::Response.new('200', JSON.generate('total' => 500, 'items' => []))
    end

    error = assert_raises(Catalog::Error) { Catalog.fetch([dataset('vector')], http: api, log: StringIO.new) }
    assert_match(/its parts list 3 products, but it has 500/, error.message)
  end

  # The API's total sometimes counts one more product than its pages hold
  def test_tolerates_a_product_the_pages_leave_out
    api = FakeApi.new({ 'Map Indices' => products(303) }, total: 304)

    assert_equal 303, Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new).products.size
  end

  # GNIS's pages repeat three of its products, and its total counts them: 304 rows are 300 products
  def test_repeated_products_are_kept_once
    rows = products(300) + products(3)
    api = FakeApi.new({ 'Map Indices' => rows }, total: 304)

    assert_equal 300, Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new).products.size
  end

  def test_a_listing_that_comes_back_short_stops_the_run
    api = FakeApi.new({ 'Map Indices' => products(250) }, total: 300)
    error = assert_raises(Catalog::Error) { Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new) }

    assert_match(/lists 300 products, but its pages held 250/, error.message)
    assert_equal 2, api.requests.count { |params| params['offset'] == '0' }, 'the query should be tried twice'
  end

  def test_refuses_a_query_too_big_to_page_through
    api = FakeApi.new({ 'Map Indices' => products(1) }, total: 400_000)
    error = assert_raises(Catalog::Error) { Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new) }

    assert_match(/more than one query can page through/, error.message)
  end

  def test_an_invalid_query_is_not_retried
    api = FakeApi.new({}, body: JSON.generate('errorMessage' => 'Invalid Query'))
    error = assert_raises(Catalog::Error) { Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new) }

    assert_match(/Invalid Query/, error.message)
    assert_equal 1, api.requests.size
  end

  def test_an_error_page_in_place_of_json_is_retried_then_stops_the_run
    api = FakeApi.new({}, body: '<html>Gateway Timeout</html>')

    assert_raises(Catalog::Error) { Catalog.fetch([dataset('mapindices')], http: api, log: StringIO.new) }
    assert_equal 3, api.requests.size
  end
end
