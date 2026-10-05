require 'json'
require 'stringio'
require 'uri'
require_relative 'catalog'
require_relative 'extent'
require_relative 'hydrologic_units'
require_relative 'http_client'
require_relative 'package'
require_relative 'places'

# Better extents for the packages whose catalog bounding box circles the globe. The catalog's boxes are a plain
# minimum and maximum, so an area on both sides of the antimeridian - Alaska, whose western Aleutians are in the
# eastern hemisphere, or the Pacific islands - gets a box from 179°W to 180°E, which puts the package in every
# spatial search and frames the whole world in a preview. The box it should have crosses the antimeridian, with
# its west past its east, as ENVELOPE allows.
#
# A state or hydrologic unit's extent comes from data/extents.json, measured from its boundary in USGS's map
# services. Those change rarely, and the services are slow, so they're kept in the file rather than fetched on
# every run: `ruby extents.rb` measures every area that needs one in the latest snapshot and rewrites it. A
# national package covers what its dataset's other packages do, so its extent is theirs together.
module Extents
  FILE = File.join(__dir__, 'data', 'extents.json')

  # Where each kind of area's boundary is drawn: states and territories by name, hydrologic units by code
  STATES_URL = 'https://carto.nationalmap.gov/arcgis/rest/services/govunits/MapServer/22'
  UNITS_URL = HydrologicUnits::SERVICE_URL

  # How far a boundary may be simplified, in degrees, for a measurement that only needs its outermost points
  GENERALIZATION = 0.001

  # The kinds of package whose area is the whole of the dataset's: national files, NHDPlus HR's national releases,
  # GNIS's national topics, and GNIS's files of all the states together
  NATIONAL_KINDS = %i[national release topic].freeze
  NATIONAL_CODES = %w[AllStates National NationalFile].freeze

  def self.boxes
    @boxes ||= File.exist?(FILE) ? JSON.parse(File.read(FILE, mode: 'r:bom|utf-8')) : {}
  end

  # A box that spans every longitude without reaching a pole: a minimum and maximum around the antimeridian. A box
  # that does reach one, like Antarctica's, really does span them all.
  def self.circles_globe?(bounds)
    west, east, north, south = bounds
    west < east && east - west > 300 && north < 89.9 && south > -89.9
  end

  # The code of the state, territory or hydrologic unit a package covers, which data/extents.json is keyed by
  def self.area(package)
    unit = package.unit
    case unit[:kind]
    when :state then Places.code(unit[:state])
    when :edition then Places.code(unit[:area])
    when :names, :gazetteer then unit[:code] if Places.name(unit[:code])
    when :hydrologic_unit then unit[:code]
    end
  end

  def self.national?(package)
    NATIONAL_KINDS.include?(package.unit[:kind]) || NATIONAL_CODES.include?(package.unit[:code])
  end

  # Gives each package whose box circles the globe a better one, where there is one: its area's from
  # data/extents.json, or for a national package, the extent of its dataset's other packages together
  # @return [Array<Package>] the packages left with a box that circles the globe
  def self.correct(packages)
    circling = packages.select { |package| package.bounds && circles_globe?(package.bounds) }
    circling.reject(&method(:national?)).each do |package|
      box = boxes[area(package).to_s]
      package.bounds = box if box
    end
    circling.select(&method(:national?)).each do |package|
      box = combined(packages.select { |other| other.dataset == package.dataset && !national?(other) })
      package.bounds = box if box
    end
    circling.select { |package| circles_globe?(package.bounds) }
  end

  # [west, east, north, south] covering the packages' boxes, crossing the antimeridian if that's narrower; nil if
  # any of them still circles the globe, which would make the whole circle the globe too
  def self.combined(packages)
    boxes = packages.filter_map(&:bounds).reject { |bounds| bounds[3] <= -89.9 }
    return nil if boxes.empty? || boxes.any? { |bounds| circles_globe?(bounds) }

    extent = Extent.new
    boxes.each { |bounds| extent.add(*bounds) }
    [*extent.longitudes, extent.north, extent.south]
  end

  # [west, east, north, south] of a boundary: each of its rings as a box of its own, together. ArcGIS splits a
  # polygon at the antimeridian, so no ring crosses it.
  def self.measure(rings)
    extent = Extent.new
    rings.each do |ring|
      longitudes, latitudes = ring.transpose
      extent.add(longitudes.min, longitudes.max, latitudes.max, latitudes.min)
    end
    [*extent.longitudes, extent.north, extent.south].map { |value| value.round(6) }
  end

  # Measures the boundary of every area whose available packages circle the globe in a snapshot, and rewrites the
  # file
  def self.refresh(snapshot_dir, http: HttpClient.new(interval: 1.0))
    bucket = Bucket.load(snapshot_dir)
    packages = Package.group(Catalog.load(snapshot_dir).products, log: StringIO.new)
                      .map { |package| package.resolve(bucket) }.select(&:available?)
    areas = packages.select { |package| package.bounds && circles_globe?(package.bounds) && !national?(package) }
                    .filter_map { |package| area(package) }.uniq.sort
    boxes = areas.to_h { |code| [code, measure(boundary(http, code))] }
    File.write(FILE, "{\n#{boxes.map { |code, box| "  #{code.to_json}: #{box.to_json}" }.join(",\n")}\n}\n")
    @boxes = nil
    boxes
  end

  # The rings of a state's or hydrologic unit's boundary, in degrees
  def self.boundary(http, code)
    url, where =
      if code.match?(/\A[A-Z]{2}\z/)
        [STATES_URL, "STATE_NAME = '#{Places.name(code)}'"]
      else
        digits = HydrologicUnits.digits(code)
        ["#{UNITS_URL}/#{HydrologicUnits::LAYERS.fetch(digits)}", "huc#{digits} = '#{code}'"]
      end
    query = { where: where, returnGeometry: true, outSR: 4326, maxAllowableOffset: GENERALIZATION, f: 'json' }
    page = JSON.parse(http.get("#{url}/query?#{URI.encode_www_form(query)}").body)
    rings = (page['features'] || []).flat_map { |feature| feature.dig('geometry', 'rings') || [] }
    raise "#{url} has no boundary for #{code}: #{page['error'] || 'no features'}" if rings.empty?

    rings
  end
end

if __FILE__ == $0
  $stdout.sync = true
  Extents.refresh(ARGV.first || 'tmp/snapshot').each { |code, box| puts "#{code}: #{box.join(', ')}" }
end
