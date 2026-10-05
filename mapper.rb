require 'json'
require_relative 'datasets'
require_relative 'extent'
require_relative 'hydrologic_units'
require_relative 'package'
require_relative 'places'

# Maps one package of The National Map's vector data to an OGM Aardvark record, and builds the collection record
# each dataset's packages are members of. Conventions follow gov.usgs.htmc, so that the two repositories' records
# read alike.
class Mapper
  PROVIDER = 'U.S. Geological Survey'
  USGS = 'Geological Survey (U.S.)'
  RIGHTS = 'USGS-authored or produced data and information are considered to be in the U.S. Public Domain.'
  PUBLIC_DOMAIN_MARK = 'https://creativecommons.org/publicdomain/mark/1.0/'

  # What GNIS's kinds of file are called
  GNIS_SERIES = { 'DomesticNames' => 'Domestic Names', 'FedCodes' => 'Federal Codes', 'Gazetteer' => 'Full Model' }.freeze
  GNIS_TOPICS = {
    'AllNames' => 'All Names', 'FeatureDescriptionHistory' => 'Feature Descriptions and Histories',
    'GovernmentUnits' => 'Government Units', 'HistoricalFeatures' => 'Historical Features',
    'PopulatedPlaces' => 'Populated Places'
  }.freeze

  # 3DHP's editions are named for federal fiscal years, which its folders carry
  FISCAL_YEAR = %r{_(?<year>FY\d{2})_}

  # e.g. "for Albany E, Massachusetts 20151103", as the retired 1 x 1 degree packages are titled
  PLACE_TITLE = /for (?<name>.+?), (?<place>[^,]+?) \d{8}\b/

  # Map a resolved package to OGM Aardvark
  # @param distinguish [Boolean] whether another package of the dataset would get the same title, so this one's
  #   needs its publication date
  def self.map(package, distinguish: false)
    new(package, distinguish: distinguish).map
  end

  def self.collection_id(dataset)
    "#{Package::ID_PREFIX}#{dataset.slug}"
  end

  # The record for one dataset, which every one of its packages is a member of. Its extent, years and modification
  # date summarize the packages, so it only changes when they do.
  def self.collection(dataset, packages)
    extent = Extent.new
    packages.filter_map(&:bounds).each { |bounds| extent.add(*bounds) }
    west, east = extent.longitudes
    envelope = format_envelope(west, east, extent.north, extent.south)
    years = packages.filter_map { |package| package.published&.[](0, 4)&.to_i }.minmax
    modified = packages.filter_map(&:last_updated).max
    compact(
      'id' => collection_id(dataset),
      'dct_title_s' => dataset.name,
      'dct_description_sm' => dataset.description || shared_description(packages),
      'dct_creator_sm' => [USGS],
      'dct_publisher_sm' => [USGS],
      'dct_temporal_sm' => years.compact.any? ? [years.uniq.join('-')] : nil,
      'gbl_indexYear_im' => years.compact.any? ? (years.first..years.last).to_a : nil,
      'gbl_dateRange_drsim' => years.compact.any? ? ["[#{years.first} TO #{years.last}]"] : nil,
      'dct_spatial_sm' => ['United States'],
      'dct_language_sm' => ['eng'],
      'schema_provider_s' => PROVIDER,
      'gbl_resourceClass_sm' => ['Collections'],
      'gbl_resourceType_sm' => dataset.resource_types,
      'dcat_theme_sm' => dataset.themes,
      'dcat_keyword_sm' => ['The National Map', dataset.keyword],
      'locn_geometry' => envelope,
      'dcat_bbox' => envelope,
      'dct_rights_sm' => [RIGHTS],
      'dct_license_sm' => [PUBLIC_DOMAIN_MARK],
      'dct_accessRights_s' => 'Public',
      'gbl_mdModified_dt' => modified&.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'gbl_mdVersion_s' => 'Aardvark',
      'dct_references_s' => dataset.services.merge('http://schema.org/url' => dataset.url).to_json
    )
  end

  # The summary most of a dataset's packages share. Ties go to the first alphabetically, so that the choice doesn't
  # depend on the order the catalog lists them in.
  def self.shared_description(packages)
    packages.map(&:descriptions).reject(&:empty?).tally.min_by { |paragraphs, count| [-count, paragraphs] }&.first
  end

  # Solr's ENVELOPE(west, east, north, south) syntax. west > east crosses the antimeridian.
  def self.format_envelope(west, east, north, south)
    "ENVELOPE(#{[west, east, north, south].map { |coordinate| format_coordinate(coordinate) }.join(', ')})"
  end

  def self.format_coordinate(value)
    format('%.8f', Float(value)).sub(/0+\z/, '').sub(/\.\z/, '')
  end

  # e.g. "8.0 MB", "3 KB" for a small file, or "22.4 GB" for a national one
  def self.size_label(bytes)
    return format('%.1f GB', bytes / 1_000_000_000.0) if bytes >= 1_000_000_000

    bytes >= 100_000 ? format('%.1f MB', bytes / 1_000_000.0) : "#{(bytes / 1000.0).ceil} KB"
  end

  # Drop fields with nothing to say, so records don't carry empty strings or arrays
  def self.compact(record)
    record.reject { |_key, field| field.nil? || (field.respond_to?(:empty?) && field.empty?) }
  end

  attr_reader :package, :dataset, :unit

  def initialize(package, distinguish: false)
    @package = package
    @dataset = package.dataset
    @unit = package.unit
    @distinguish = distinguish
  end

  # The package's title, without the date that tells it apart from a namesake
  def base_title
    "USGS #{name_and_subject}"
  end

  # Keys follow the order of gov.usgs.htmc's records, so that diffs between runs read in a familiar order
  # @return [Hash]
  def map
    self.class.compact(
      'id' => package.id,
      'dct_title_s' => title,
      'dct_description_sm' => package.descriptions,
      'dct_creator_sm' => [USGS],
      'dct_publisher_sm' => [USGS],
      'dct_issued_s' => package.published,
      'dct_temporal_sm' => year ? [year.to_s] : nil,
      'gbl_indexYear_im' => year ? [year] : nil,
      'dct_spatial_sm' => spatial,
      'dct_language_sm' => ['eng'],
      'schema_provider_s' => PROVIDER,
      'dct_identifier_sm' => package.sciencebase_urls,
      'gbl_resourceClass_sm' => ['Datasets'],
      'gbl_resourceType_sm' => dataset.resource_types,
      'dcat_theme_sm' => themes,
      'dcat_keyword_sm' => keywords,
      'dct_format_s' => Package::FORMATS.dig(package.downloads.first&.format, 1),
      'locn_geometry' => envelope,
      'dcat_bbox' => envelope,
      'dcat_centroid' => centroid,
      'pcdm_memberOf_sm' => [self.class.collection_id(dataset)],
      'dct_rights_sm' => [RIGHTS],
      'dct_license_sm' => [PUBLIC_DOMAIN_MARK],
      'dct_accessRights_s' => 'Public',
      'gbl_mdModified_dt' => modified,
      'gbl_mdVersion_s' => 'Aardvark',
      'dct_references_s' => references.to_json
    )
  end

  private

  def title
    @distinguish && package.published ? "#{base_title} (published #{package.published})" : base_title
  end

  # What the package is, as its title words it: "National Boundary Dataset (NBD) for Iowa". Small-scale datasets
  # go by USGS's own names for them.
  def name_and_subject
    return small_scale_name if unit[:kind] == :small_scale

    "#{dataset.name.delete_prefix('USGS ').delete_suffix(' Best Resolution')} #{subject}"
  end

  # What the package covers: "for Iowa", "for the Upper Wabash Subbasin (HU-8 05120101)"
  def subject
    case unit[:kind]
    when :state then "for #{state_name}"
    when :national then 'for the United States'
    when :hydrologic_unit then "for #{hydrologic_unit}"
    when :release then "for the United States, Release #{unit[:release]}"
    when :edition then "for #{edition_area}#{" (#{fiscal_year})" if fiscal_year}"
    when :names then "#{GNIS_SERIES.fetch(unit[:series])} for #{gnis_place}"
    when :topic then "#{GNIS_TOPICS.fetch(unit[:topic], spaced(unit[:topic]))} for the United States"
    when :gazetteer
      unit[:code] == 'NationalFile' ? "National File (#{package.published})" : "State Gazetteer File for #{gnis_place} (#{package.published})"
    when :tile then "for #{tile_name}, #{tile_place || unit[:code]} (1 x 1 Degree)"
    when :quadrangle then "for #{[spaced(unit[:name]), unit[:code]].compact.join(', ')}"
    when :degree then "for #{degree_title[:name]}, #{degree_title[:place]} (1 x 1 Degree)"
    else "for #{spaced(unit[:stem])}"
    end
  end

  # e.g. "the Upper Wabash Subbasin (HU-8 05120101)", or "Hydrologic Unit 05120101" if the name isn't known
  def hydrologic_unit
    code = unit[:code]
    name = HydrologicUnits.name(code)
    label = "HU-#{HydrologicUnits.digits(code)} #{code}"
    return "Hydrologic Unit #{code}" unless name

    level = HydrologicUnits.level(code)
    # Region names already end in "Region"
    name.end_with?(level) ? "the #{name} (#{label})" : "the #{name} #{level} (#{label})"
  end

  def edition_area
    unit[:area] == 'CONUS' ? 'the Conterminous United States' : unit[:area]
  end

  def fiscal_year
    package.downloads.filter_map { |download| download.url[FISCAL_YEAR, :year] }.first
  end

  def state_name
    Places.canonical(unit[:state])
  end

  # GNIS files are for a state, all the states together, the nation, or Antarctica
  def gnis_place
    case unit[:code]
    when 'AllStates' then 'All States'
    when 'National', 'NationalFile' then 'the United States'
    when 'Antarctica' then 'Antarctica'
    else Places.name(unit[:code]) || unit[:code]
    end
  end

  # USGS's own title, without the series name, edition month and format: "1:1,000,000-Scale State Boundaries of
  # the United States"
  def small_scale_name
    package.primary['title'].to_s.split.join(' ')
           .sub(/\AUSGS\s+/, '').sub(/\ASmall-scale Dataset - /, '').sub(/\s+\d{6}\b.*\z/, '')
  end

  def tile_name
    title_match = package.primary['title'].to_s.split.join(' ')[Package::TILE_TITLE, :name]
    title_match || spaced(unit[:name])
  end

  def tile_place
    unit[:place] || Places.name(unit[:code])
  end

  def degree_title
    package.primary['title'].to_s.split.join(' ').match(PLACE_TITLE) || { name: spaced(unit[:name]), place: '' }
  end

  def spaced(text)
    text.to_s.tr('_', ' ').squeeze(' ').strip
  end

  def year
    package.published&.[](0, 4)&.to_i
  end

  # Places the package covers, named as gov.usgs.htmc names them. Hydrologic units cross state lines, so they
  # get none.
  def spatial
    case unit[:kind]
    when :state then [state_name]
    when :national, :release, :topic then ['United States']
    when :edition then [unit[:area] == 'CONUS' ? 'United States' : unit[:area]]
    when :names, :gazetteer
      place = gnis_place
      [place.start_with?('the ') || place == 'All States' ? 'United States' : place]
    when :small_scale then small_scale_places
    when :tile then [tile_place].compact
    when :quadrangle then [Places.name(unit[:code])].compact
    when :degree then [degree_title[:place]].reject(&:empty?)
    else []
    end
  end

  def small_scale_places
    title = package.primary['title'].to_s
    places = (Places::US_STATES.values + Places::US_TERRITORIES.values + ['U.S. Virgin Islands'])
             .select { |place| title.include?(place) }.map { |place| Places.canonical(place) }.uniq
    places.empty? ? ['United States'] : places
  end

  def themes
    return dataset.themes unless dataset.slug == 'smallscale'

    package.tags.flat_map { |tag| Datasets::SMALL_SCALE_THEMES.fetch(tag, []) }.uniq
  end

  def keywords
    level =
      case unit[:kind]
      when :state then 'State'
      when :national, :release, :topic then 'National'
      when :hydrologic_unit then "HU-#{HydrologicUnits.digits(unit[:code])} #{HydrologicUnits.level(unit[:code])}"
      when :names then GNIS_SERIES[unit[:series]]
      when :tile, :degree then '1 x 1 degree'
      when :quadrangle then '7.5 x 7.5 minute'
      end
    ['The National Map', dataset.keyword, level].compact.uniq
  end

  def bounds
    @bounds ||= package.bounds
  end

  def envelope
    bounds && self.class.format_envelope(*bounds)
  end

  # "latitude,longitude" of the package's center. A box whose west is past its east crosses the antimeridian, so
  # its center is halfway along the way round that does.
  def centroid
    return nil unless bounds

    west, east, north, south = bounds
    longitude = west > east ? (west + east + 360) / 2 : (west + east) / 2
    longitude -= 360 if longitude > 180
    "#{self.class.format_coordinate((north + south) / 2)},#{self.class.format_coordinate(longitude)}"
  end

  def modified
    time = package.last_updated
    return time.strftime('%Y-%m-%dT%H:%M:%SZ') if time

    published = package.published
    published && "#{published.length == 4 ? "#{published}-01-01" : published}T00:00:00Z"
  end

  # Services first, as gov.usgs.htmc puts its COG first: they're what a viewer previews
  def references
    downloads = package.downloads.map do |download|
      label = Package::FORMATS.fetch(download.format, [download.format.to_s]).first
      { 'url' => download.url, 'label' => download.size ? "#{label} (#{self.class.size_label(download.size)})" : label }
    end
    self.class.compact(
      dataset.services.merge(
        'http://schema.org/downloadUrl' => downloads,
        'http://www.opengis.net/cat/csw/csdgm' => package.metadata_url,
        'http://schema.org/url' => package.primary['metaUrl'],
        'http://schema.org/thumbnailUrl' => package.thumbnail_url
      )
    )
  end
end
