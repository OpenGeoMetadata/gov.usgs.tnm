require 'json'
require 'uri'
require_relative 'datasets'
require_relative 'http_client'
require_relative 'snapshot'

# Every product The National Map lists under this repository's datasets, from its TNM Access API. A product is one
# file: The National Map lists each format of a package separately.
class Catalog
  API_URL = 'https://tnmaccess.nationalmap.gov/api/v1/products'
  PAGE_SIZE = 1000

  # The API answers an offset past about 166,000 with "Invalid Query", so no single query can list more
  MAX_OFFSET = 165_000

  # The API's total sometimes counts a product more than its pages hold. A few missing is tolerated; more means
  # the listing came back incomplete, and nothing should be withdrawn on the strength of it. Its pages also repeat
  # a few products, whatever their size, and its total counts the repeats: GNIS's 304 are 300 products.
  MAX_SHORTFALL = 0.005

  # The fields a product keeps. The rest of what the API returns is left out of the snapshot.
  FIELDS = %w[title body sourceId metaUrl vendorMetaUrl publicationDate lastUpdated downloadURL urls
              previewGraphicURL boundingBox format extent].freeze

  PRODUCTS_FILE = 'products.jsonl'

  class Error < StandardError; end

  def self.fetch(datasets = Datasets::ALL, http: HttpClient.new, log: $stdout)
    new(datasets.flat_map { |dataset| dataset.tags.flat_map { |tag| fetch_tag(http, dataset, tag, log) } })
  end

  def self.load(dir)
    new(Snapshot.read(dir, PRODUCTS_FILE))
  end

  # A dataset too big for one query is fetched in parts, and the parts have to add up to the whole: a format
  # The National Map adds would otherwise go unnoticed
  def self.fetch_tag(http, dataset, tag, log)
    parts = partitions(dataset).map { |params| fetch_query(http, { 'datasets' => tag }.merge(params)) }
    products = parts.flat_map(&:last)
    if parts.size > 1
      rows = parts.sum(&:first)
      total = request(http, { 'datasets' => tag, 'max' => 1 })['total'].to_i
      raise Error, "#{tag}: its parts list #{rows} products, but it has #{total}" if short?(rows, total)
    end
    log.puts "#{tag}: #{products.size} products"
    products.map { |product| product.slice(*FIELDS).merge('dataset_tag' => tag) }
  end

  def self.partitions(dataset)
    return [{}] unless dataset.partitions

    dataset.partitions.flat_map { |param, values| values.map { |value| { param => value } } }
  end

  # Pages through one query. The API gives no order for its results, so if pages shift as products change
  # mid-listing, the query is run once more before giving up.
  # @return [Array(Integer, Array<Hash>)] how many rows the pages held, and the products without repeats
  def self.fetch_query(http, params, attempts: 2)
    attempts.times do |attempt|
      total, rows = page_through(http, params)
      # A ScienceBase item can hold more than one product's file, so a product is its item and file together
      return [rows.size, rows.uniq { |product| [product['sourceId'], product['downloadURL']] }] unless short?(rows.size, total)
      raise Error, "#{params} lists #{total} products, but its pages held #{rows.size}" if attempt == attempts - 1
    end
  end

  def self.page_through(http, params)
    products = []
    total = nil
    loop do
      page = request(http, params.merge('max' => PAGE_SIZE, 'offset' => products.size))
      total ||= page['total'].to_i
      if total > MAX_OFFSET + PAGE_SIZE
        raise Error, "#{params} lists #{total} products, more than one query can page through; split it into parts"
      end

      items = page['items'] || []
      products.concat(items)
      return [total, products] if items.empty? || products.size >= total
    end
  end

  def self.short?(count, total)
    total - count > (total * MAX_SHORTFALL).ceil
  end

  # The API sometimes answers with an error page in place of JSON when it's busy, which is worth asking again
  # about; an "Invalid Query" isn't
  def self.request(http, params, attempts: 3)
    url = "#{API_URL}?#{URI.encode_www_form(params)}"
    attempts.times do |attempt|
      response = http.get(url)
      begin
        page = JSON.parse(response.body.to_s)
        raise Error, "#{url}: #{page['errorMessage']}" if page.is_a?(Hash) && page['errorMessage']
        return page if response.is_a?(Net::HTTPSuccess) && page.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
      raise Error, "#{url} answered #{response.code} without a usable listing" if attempt == attempts - 1
    end
  end

  attr_reader :products

  def initialize(products)
    @products = products
  end

  def save(dir)
    Snapshot.write(dir, PRODUCTS_FILE, products)
  end

  # Every file the products link: their downloads and thumbnails
  def urls
    (download_urls + products.map { |product| product['previewGraphicURL'] }).compact.uniq
  end

  # The files the products are downloads of, including NHDPlus HR's rasters
  def download_urls
    products.flat_map { |product| [product['downloadURL'], *(product['urls'] || {}).values] }
            .compact.map(&:strip).reject(&:empty?).uniq
  end
end
