require 'json'
require 'net/http'
require 'uri'

# Names of the hydrologic units that hydrography packages are cut by, e.g. "Upper Wabash" for 05120101. The
# products' titles give only the codes, so the names come from the Watershed Boundary Dataset's map service.
#
# They're kept in data/hydrologic-units.json rather than fetched on every run: the hydrography service is
# often slow or down, and a name that came and went with it would change hundreds of records each time.
# Run `ruby hydrologic_units.rb` to refresh the file.
module HydrologicUnits
  FILE = File.join(__dir__, 'data', 'hydrologic-units.json')
  SERVICE_URL = 'https://hydro.nationalmap.gov/arcgis/rest/services/wbd/MapServer'

  # The service's layer for each level of unit, keyed by the length of its code
  LAYERS = { 2 => 1, 4 => 2, 8 => 4 }.freeze

  # What each level is called, keyed by the length of its code
  LEVELS = { 2 => 'Region', 4 => 'Subregion', 8 => 'Subbasin' }.freeze

  def self.names
    @names ||= JSON.parse(File.read(FILE, mode: 'r:bom|utf-8'))
  end

  # e.g. "Upper Wabash" for "05120101"; nil for a code the file doesn't have
  def self.name(code)
    names["huc#{code.to_s.length}"]&.[](code.to_s)
  end

  # e.g. "Subbasin" for an 8-digit code
  def self.level(code)
    LEVELS[digits(code)]
  end

  # How many digits a code has: its level. NHDPlus HR's Great Lakes subregions have codes like "0418i".
  def self.digits(code)
    code.to_s.count('0-9')
  end

  # Fetches every region, subregion and subbasin name from the service and rewrites the file
  def self.refresh
    names = LAYERS.to_h { |digits, layer| ["huc#{digits}", fetch_layer(layer, "huc#{digits}")] }
    File.write(FILE, "#{JSON.pretty_generate(names.transform_values { |units| units.sort.to_h })}\n")
    names.transform_values(&:size)
  end

  def self.fetch_layer(layer, field)
    units = {}
    loop do
      query = { where: '1=1', outFields: "#{field},name", returnGeometry: false, orderByFields: field,
                resultOffset: units.size, resultRecordCount: 2000, f: 'json' }
      uri = URI("#{SERVICE_URL}/#{layer}/query?#{URI.encode_www_form(query)}")
      page = JSON.parse(Net::HTTP.get(uri))
      raise "#{uri} failed: #{page['error']}" if page['error']

      features = page['features'] || []
      features.each { |feature| units[feature['attributes'][field]] = feature['attributes']['name'] }
      return units unless page['exceededTransferLimit'] && features.any?
    end
  end
end

puts HydrologicUnits.refresh.map { |level, count| "#{level}: #{count}" }.join(', ') if __FILE__ == $0
