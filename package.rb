require 'cgi/escape'
require 'time'
require_relative 'bucket'
require_relative 'datasets'
require_relative 'hydrologic_units'
require_relative 'places'

# One record's worth of The National Map: a dataset's data for one area - a state, a hydrologic unit, a
# 7.5-minute quadrangle - which The National Map lists as a separate product for each file format.
class Package
  ID_PREFIX = 'usgs-tnm-'

  # Each format's label on a download, and its name in OpenGeoMetadata's list of format values. In the order
  # downloads are listed, which is also the order of preference for a record's one dct_format_s.
  FORMATS = {
    gpkg: ['GeoPackage', 'GeoPackage'],
    gdb: ['File geodatabase', 'Geodatabase'],
    shp: ['Shapefile', 'Shapefile'],
    txt: ['Text (pipe-delimited)', 'Tabular Data'],
    raster: ['Rasters (GeoTIFF)', 'GeoTIFF']
  }.freeze

  # The suffixes and folder names that say what format a file is in
  FORMAT_NAMES = {
    'gdb' => :gdb, 'filegdb' => :gdb, 'filegdb101' => :gdb, 'gpkg' => :gpkg, 'shape' => :shp, 'shp' => :shp,
    'text' => :txt, 'raster' => :raster
  }.freeze

  FORMAT = '(?<format>GDB|GPKG|Gpkg|Shape|Text|RASTER|Raster)'
  STATE = '(?<state>[A-Za-z_]+?)'

  # How each dataset names its files, and what the name says about the area the file covers, tried in order.
  # A name with no format suffix gets its format from its folder.
  PATTERNS = {
    'nbd' => [[/\AGOVTUNIT_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
              [/\AGovernmentUnits_National_#{FORMAT}\.zip\z/, :national]],
    'nsd' => [[/\ASTRUCT_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
              [/\AStructures_National_#{FORMAT}\.zip\z/, :national]],
    'ntd' => [[/\ATRAN_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
              [/\ATransportation_National_#{FORMAT}\.zip\z/, :national]],
    'woodland' => [[/\ALNDCVR_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
                   [/\ALandcover_National_#{FORMAT}\.zip\z/, :national]],
    'mapindices' => [[/\AMAPINDICES_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
                     [/\AMapIndices_National_#{FORMAT}\.zip\z/, :national]],
    'nhd' => [[/\ANHD_H_(?<code>\d{8}|\d{4})_HU[48]_#{FORMAT}\.zip\z/, :hydrologic_unit],
              [/\ANHD_H_#{STATE}_State_#{FORMAT}\.zip\z/, :state],
              [/\ANHD_H_National_#{FORMAT}\.zip\z/, :national]],
    # Some subregions' files carry the date of their edition and others don't, and the Great Lakes' have codes
    # with a trailing "i"
    'nhdplushr' => [[/\ANHDPLUS_H_(?<code>\d{8}|\d{4}i?)_HU[48](?:_(?<date>\d{8}))?_#{FORMAT}\.zip\z/, :hydrologic_unit],
                    [/\ANHDPlus_H_National_Release_(?<release>\d+)_#{FORMAT}\.zip\z/, :release]],
    'wbd' => [[/\AWBD_(?<code>\d{2})_HU2_#{FORMAT}\.zip\z/, :hydrologic_unit],
              [/\AWBD_National_#{FORMAT}\.zip\z/, :national]],
    # Each year's edition is published alongside the last
    '3dhp' => [[/\A3dhp_all_(?<area>CONUS|Alaska)_(?<date>\d{8})_#{FORMAT}\.zip\z/, :edition]],
    'gnis' => [[/\A(?<series>DomesticNames|FedCodes)_(?<code>[A-Z]{2}|AllStates|National)_#{FORMAT}\.zip\z/, :names],
               [/\A(?<series>Gazetteer)_(?<code>[A-Z]{2}|Antarctica)_#{FORMAT}\.zip\z/, :names],
               [/\A(?<topic>[A-Za-z]+)_National_#{FORMAT}\.zip\z/, :topic],
               # The state gazetteer files GNIS published until 2017, in pipe-delimited text
               [/\A(?<code>[A-Z]{2}|AllStates|NationalFile)(?:_Features)?\.zip\z/, :gazetteer, :txt]],
    'smallscale' => [[/\A(?<name>[a-z0-9_]+?)[._](?<format>gdb|shp)_nt\d+\.tar\.gz\z/, :small_scale]],
    # Tiles on the Canadian border write the province's code against "1X1"; older tiles have a number instead
    # of a state's code, and sometimes no format suffix
    'contours' => [[/\AELEV_(?<name>.+?)_(?<code>[A-Z]{2})_?1X1_#{FORMAT}\.zip\z/, :tile],
                   [/\AElev_(?<number>\d+)_(?<name>.+?)_1X1(?:_#{FORMAT})?\.zip\z/, :tile],
                   [/\AElevation_National_#{FORMAT}\.zip\z/, :national]],
    # A quadrangle outside any state has "None" for its state's code
    'vector' => [[/\AVECTOR_(?<name>.+)_(?<code>[A-Z]{2}|None)_7_5_Min_#{FORMAT}\.zip\z/, :quadrangle],
                 # Retired 1 x 1 degree packages, whose formats are told apart only by their folders
                 [/\AVECTOR_(?<number>\d+)_(?<name>.+)_1X1\.zip\z/, :degree]]
  }.freeze

  # What a product title says that its file name doesn't: a quadrangle's GNIS cell, and the place a contour tile
  # is filed under
  QUADRANGLE_TITLE = /\(Vector\)\s+(?<cell>\d+)\s+/
  # Contour tiles are titled two ways: "Contours for Aberdeen E, South Dakota 20200826 1 X 1 degree" and
  # "Contours for Ames E, Iowa 1 x 1 degree (published 20231201)"
  TILE_TITLE = /Contours for (?<name>.+?), (?<place>[^,]+?) (?:\d{8}\b|1 [Xx] 1 degree)/

  HTML_TAG = %r{</?[a-z][^>]*>}i

  # One file of a package. size is nil when the file isn't on The National Map's S3 bucket, so can't be measured.
  Download = Data.define(:url, :format, :size)

  # @param products [Array<Hash>] products from the Catalog, each with its 'dataset_tag'
  # @return [Array<Package>] one per area of each dataset, each holding its products in every format
  def self.group(products, log: $stdout)
    groups = {}
    unrecognized = Hash.new(0)
    products.each do |product|
      dataset = Datasets.for_tag(product['dataset_tag'])
      next unless dataset

      urls(product).each do |url|
        unit, format = parse(dataset, url, product)
        unrecognized[dataset.slug] += 1 if unit[:kind] == :other
        key = [dataset.slug, unit_key(unit)]
        (groups[key] ||= new(dataset, unit)).add(product, url, format, unit)
      end
    end
    unrecognized.each { |slug, count| log.puts "#{count} #{slug} files have names the harvester doesn't recognize" }
    groups.values
  end

  # Every file a product links: its download, and for NHDPlus HR its rasters. The catalog encodes a few file
  # names twice - an apostrophe as %2527 rather than %27 - and those URLs don't resolve as given.
  def self.urls(product)
    ([product['downloadURL']] + (product['urls'] || {}).values).compact.map(&:strip).reject(&:empty?)
                                                                .map { |url| url.gsub(/%25(\h\h)/, '%\\1') }.uniq
  end

  # @return [Array(Hash, Symbol)] what the file name says about the area it covers, and the file's format
  def self.parse(dataset, url, product)
    path = Bucket.path(url)
    name = File.basename(path)
    folder = File.basename(File.dirname(path))
    PATTERNS.fetch(dataset.slug, []).each do |pattern, kind, default_format|
      match = pattern.match(name)
      next unless match

      unit = match.named_captures.transform_keys(&:to_sym).compact.merge(kind: kind)
      format = format_named(unit.delete(:format)) || format_named(folder) || default_format || :other
      return [refine(unit, product), format]
    end
    [{ kind: :other, stem: name.sub(/(\.tar)?\.[^.]+\z/, '') }, format_named(folder) || :other]
  end

  def self.format_named(name)
    FORMAT_NAMES[name.to_s.downcase]
  end

  # Adds what the product's title says to what its file name did
  def self.refine(unit, product)
    title = product['title'].to_s.split.join(' ')
    case unit[:kind]
    when :quadrangle
      unit = unit.except(:code) if unit[:code] == 'None'
      unit.merge(cell: title[QUADRANGLE_TITLE, :cell]).compact
    when :tile
      place = title[TILE_TITLE, :place]
      unit.merge(code: unit[:code] || Places.code(place), place: place).compact
    else
      unit
    end
  end

  # What a package's files have in common: their area, without the format or what only the title says. A
  # hydrologic unit's files are one package whether or not their names carry the edition's date; 3DHP's
  # editions are packages of their own, because each stays available after the next is published.
  #
  # A quadrangle is its GNIS cell, which survives the quadrangle being renamed: some cells' GeoPackages carry a
  # newer name than their other formats, or the same name spelled differently.
  def self.unit_key(unit)
    return "kind=quadrangle|cell=#{unit[:cell]}" if unit[:kind] == :quadrangle && unit[:cell]

    shared = unit.except(:place, :cell)
    shared = shared.except(:date) if unit[:kind] == :hydrologic_unit
    shared.sort.map { |key, value| "#{key}=#{value}" }.join('|')
  end

  # e.g. "nbd-ia" for Iowa's boundaries, "nhd-hu8-05120101", "vector-47611" for Washington West's
  def self.local_id(dataset, unit)
    suffix =
      case unit[:kind]
      when :state then Places.code(unit[:state])&.downcase || slug(unit[:state])
      when :national then 'national'
      when :hydrologic_unit then "hu#{HydrologicUnits.digits(unit[:code])}-#{unit[:code]}"
      when :release then "national-release-#{unit[:release]}"
      when :edition then "#{unit[:area].downcase}-#{unit[:date]}"
      when :names then "#{unit[:series] == 'Gazetteer' ? 'fullmodel' : unit[:series].downcase}-#{unit[:code].downcase}"
      when :topic then "#{unit[:topic].downcase}-national"
      when :gazetteer then "gazetteer-#{unit[:code].downcase}"
      when :small_scale then slug(unit[:name])
      when :tile then [unit[:code]&.downcase || 'other', slug(unit[:name]), unit[:number]].compact.join('-')
      when :quadrangle then unit[:cell] || [unit[:code]&.downcase, slug(unit[:name])].compact.join('-')
      when :degree then "1x1-#{unit[:number]}"
      else slug(unit[:stem])
      end
    "#{dataset.slug}-#{suffix}"
  end

  def self.slug(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
  end

  # A product summary's paragraphs. Summaries are plain text, wrapped and indented as the metadata they were copied
  # from, or now and then HTML, whose line breaks and blocks are its paragraphs.
  def self.paragraphs(text)
    text = text.to_s
    if text.match?(HTML_TAG)
      text = CGI.unescapeHTML(text.gsub(%r{<br\s*/?>|</(?:div|p)>}i, "\n\n").gsub(HTML_TAG, '').gsub('&nbsp;', ' '))
    end
    text.split(/\n\s*\n/).map { |paragraph| paragraph.split.join(' ') }.reject(&:empty?)
  end

  attr_reader :dataset, :unit, :downloads, :thumbnail_url, :metadata_url

  def initialize(dataset, unit)
    @dataset = dataset
    @unit = unit
    @files = {}
  end

  # Keeps one file per format: the one from the product published last, should a format be listed twice. The
  # package is named for its latest product, which matters for a quadrangle its formats name differently.
  def add(product, url, format, unit = nil)
    published = product['publicationDate'].to_s
    if unit && published > @latest.to_s
      @latest = published
      @unit = unit
    end

    current = @files[format]
    return if current && current[:url] != url && current[:product]['publicationDate'].to_s >= published

    @files[format] = { url: url, product: product }
  end

  def id
    "#{ID_PREFIX}#{self.class.local_id(dataset, unit)}"
  end

  # Products in the order of their formats' preference
  def products
    ordered_files.map { |_format, file| file[:product] }.uniq
  end

  # The product of the package's preferred format, whose title, links and extent the record uses
  def primary
    products.first
  end

  def tags
    products.map { |product| product['dataset_tag'] }.uniq
  end

  # Checks each file against the bucket listing, measuring the ones that are there and dropping the ones that
  # aren't, and finds the thumbnail and metadata USGS publishes beside them
  # @return [self]
  def resolve(bucket)
    @downloads = ordered_files.filter_map do |format, file|
      available, size = bucket.file(file[:url])
      Download.new(url: file[:url], format: format, size: size) if available
    end
    @thumbnail_url = beside(bucket, '.jpg') || listed(bucket, primary['previewGraphicURL'])
    @metadata_url = beside(bucket, '.xml') || primary['vendorMetaUrl']
    self
  end

  # Whether any of the package's files can be downloaded
  def available?
    downloads.any?
  end

  # The latest publication date among the package's products, as The National Map gives it (YYYY-MM-DD, or
  # just a year for the oldest)
  def published
    products.map { |product| product['publicationDate'].to_s.strip }.reject(&:empty?).max
  end

  def last_updated
    products.filter_map { |product| parse_time(product['lastUpdated']) }.max
  end

  # A better box than the catalog's, for one that circles the globe: see Extents
  attr_writer :bounds

  # [west, east, north, south] of the primary product's bounding box, unless a better one has been set
  def bounds
    return @bounds if @bounds

    box = products.map { |product| product['boundingBox'] }.compact.first
    box && [box['minX'], box['maxX'], box['maxY'], box['minY']].map { |value| Float(value) }
  rescue ArgumentError, TypeError
    nil
  end

  def sciencebase_urls
    products.filter_map { |product| product['metaUrl'] }.uniq.sort
  end

  # USGS's own description of the package: the summary The National Map gives each of its products, which is the
  # abstract of the product's metadata. A package's formats have so far always shared one; should they differ,
  # the record gets each.
  def descriptions
    products.flat_map { |product| self.class.paragraphs(product['body']) }.uniq
  end

  private

  def ordered_files
    @files.sort_by { |format, _file| FORMATS.keys.index(format) || FORMATS.size }
  end

  # A file USGS publishes beside one of the package's downloads, with the given extension in place of the
  # download's, if the bucket has one; the preferred format's first
  def beside(bucket, extension)
    downloads.each do |download|
      url = download.url.sub(/(\.tar)?\.[^.\/]+\z/, extension)
      return url if url != download.url && bucket.file(url).first && Bucket.key(url)
    end
    nil
  end

  # The URL, if it's on the bucket and listed there
  def listed(bucket, url)
    url if url && Bucket.key(url) && bucket.file(url).first
  end

  def parse_time(text)
    Time.iso8601(text.to_s).utc
  rescue ArgumentError
    nil
  end
end
