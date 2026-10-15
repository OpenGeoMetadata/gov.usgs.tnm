require 'json'
require_relative 'mapper'
require_relative 'tiles'

# An index map of one of 3DEP's seamless DEMs: the outline of every tile with a record, as OpenIndexMaps GeoJSON
# (https://openindexmaps.org/specification/1.0.0), and the record that points to it. A tile is found on the map
# rather than by name, since its name is only a grid reference.
class IndexMap
  ID_PREFIX = "#{Package::ID_PREFIX}index-".freeze

  # The datasets that get an index map, and what each calls its tiles
  DATASETS = { 'dem13' => 'tile', 'dem1' => 'tile', 'dem2' => 'tile', 's1m' => 'cell' }.freeze

  # Index maps are generated here rather than by USGS, so they carry this repository's own license
  RIGHTS = 'This index map is dedicated to the public domain under CC0 1.0. The data it outlines is in the U.S. ' \
           'Public Domain.'
  CC0 = 'https://creativecommons.org/publicdomain/zero/1.0/'

  def self.id(dataset)
    "#{ID_PREFIX}#{dataset.slug}"
  end

  # One index map for each dataset that has one, from its published packages
  def self.build(packages)
    packages.group_by(&:dataset).filter_map { |dataset, members| new(dataset, members) if DATASETS.key?(dataset.slug) }
  end

  attr_reader :dataset, :packages

  def initialize(dataset, packages)
    @dataset = dataset
    @packages = packages.sort_by(&:id)
  end

  def id
    self.class.id(dataset)
  end

  # The GeoJSON, one outline to a line so that a change to one tile changes one line
  def geojson
    lines = packages.map { |package| JSON.generate(feature(package)) }
    "{\"type\":\"FeatureCollection\",\"features\":[\n#{lines.join(",\n")}\n]}\n"
  end

  # @param url [String] where the GeoJSON is published
  # @param bytes [Integer] the GeoJSON's size
  # @param fgdc_url [String, nil] the elevation model's own FGDC, which says what its tiles' values measure
  def record(url, bytes, fgdc_url = nil)
    noun = DATASETS.fetch(dataset.slug)
    envelope, years, modified = Mapper.summary(packages)
    Mapper.compact(
      'id' => id,
      'dct_title_s' => "Index to #{dataset.name} #{noun.capitalize}s",
      'dct_creator_sm' => [Mapper::USGS],
      'dct_publisher_sm' => [Mapper::USGS],
      'dct_temporal_sm' => years.compact.any? ? [years.uniq.join('-')] : nil,
      'gbl_indexYear_im' => years.compact.any? ? (years.first..years.last).to_a : nil,
      'gbl_dateRange_drsim' => years.compact.any? ? ["[#{years.first} TO #{years.last}]"] : nil,
      'dct_spatial_sm' => ['United States'],
      'dct_language_sm' => ['eng'],
      'schema_provider_s' => Mapper::PROVIDER,
      'gbl_resourceClass_sm' => ['Maps'],
      'gbl_resourceType_sm' => ['Index maps'],
      'dcat_theme_sm' => dataset.themes,
      'dcat_keyword_sm' => ['The National Map', dataset.keyword],
      'dct_format_s' => 'GeoJSON',
      'locn_geometry' => envelope,
      'dcat_bbox' => envelope,
      'pcdm_memberOf_sm' => [Mapper.collection_id(dataset)],
      'dct_rights_sm' => [RIGHTS],
      'dct_license_sm' => [CC0],
      'dct_accessRights_s' => 'Public',
      'gbl_mdModified_dt' => modified&.strftime('%Y-%m-%dT%H:%M:%SZ'),
      'gbl_mdVersion_s' => 'Aardvark',
      'dct_references_s' => {
        'https://openindexmaps.org' => url,
        'http://schema.org/downloadUrl' => [{ 'url' => url, 'label' => "GeoJSON (#{Mapper.size_label(bytes)})" }],
        'http://www.opengis.net/cat/csw/csdgm' => fgdc_url
      }.compact.to_json
    )
  end

  private

  def feature(package)
    mapper = Mapper.new(package)
    {
      'type' => 'Feature',
      'properties' => Mapper.compact(
        'label' => package.unit[:tile] || package.unit[:code],
        'title' => mapper.base_title,
        'datePub' => package.published&.[](0, 4),
        'publisher' => 'U.S. Geological Survey',
        'available' => true,
        'recId' => package.id,
        'websiteUrl' => package.primary['metaUrl'],
        'download' => package.downloads.first&.url,
        'thumbUrl' => package.thumbnail_url
      ),
      'geometry' => { 'type' => 'Polygon', 'coordinates' => [outline(package)] }
    }
  end

  # The tile's corners, counterclockwise and closed, as GeoJSON wants an outer ring
  def outline(package)
    corners =
      if package.unit[:kind] == :s1m_cell
        Tiles.cell_corners(package.unit[:code])
      else
        west, east, north, south = Tiles.degree_box(package.unit[:tile])
        [[west, south], [east, south], [east, north], [west, north]]
      end
    (corners + [corners.first]).map { |point| point.map { |value| value.round(6) } }
  end
end
