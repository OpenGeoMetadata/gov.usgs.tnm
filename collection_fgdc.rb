require 'json'
require 'net/http'
require_relative 'datasets'
require_relative 'http_client'
require_relative 'snapshot'

# The FGDC record USGS publishes for each dataset as a whole, which its collection record links, and an elevation
# model's index map as well. For the elevation models it's also where a viewer drawing an index map's tiles as one
# mosaic reads what their values measure, which neither a tile's GeoTIFF nor the index map says: its vertical datum
# and units.
#
# USGS keeps it as a file on the dataset's ScienceBase collection item (see Dataset#sciencebase_item), and
# ScienceBase serves a file by a hash of its contents rather than by its name, so the link changes whenever USGS
# revises the file. It's looked up from the item on each run rather than written down here.
class CollectionFgdc
  ITEM_URL = 'https://www.sciencebase.gov/catalog/item'
  FGDC_TYPE = 'application/fgdc+xml'
  FILE = 'collection-fgdc.jsonl'

  class Error < StandardError; end

  # Each dataset's collection item, by its slug, for the datasets that have one
  def self.items(datasets = Datasets::ALL)
    datasets.to_h { |dataset| [dataset.slug, dataset.sciencebase_item] }.compact
  end

  # An item that has no FGDC file gets no link, rather than failing the run: a record is complete without one
  def self.fetch(items = self.items, http: HttpClient.new, log: $stdout)
    urls = items.to_h { |slug, item| [slug, fgdc_url(http, item)] }.compact
    log.puts "ScienceBase: FGDC records for #{urls.size} of the #{items.size} datasets with a collection item"
    new(urls)
  end

  def self.fgdc_url(http, item)
    url = "#{ITEM_URL}/#{item}?format=json"
    response = http.get(url)
    raise Error, "#{url} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    files = JSON.parse(response.body).fetch('files', [])
    files.find { |file| file['contentType'] == FGDC_TYPE }&.fetch('url', nil)
  end

  def self.load(dir)
    new(Snapshot.read(dir, FILE).to_h { |slug, url| [slug, url] })
  end

  # @param urls [Hash{String => String}] each dataset's FGDC, by its slug
  def initialize(urls)
    @urls = urls
  end

  # @return [String, nil] the dataset's FGDC, if USGS publishes one
  def url(slug)
    @urls[slug]
  end

  def save(dir)
    Snapshot.write(dir, FILE, @urls.sort.map { |slug, url| [slug, url] })
  end
end
