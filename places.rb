# Place names for the state and territory codes and names that appear in The National Map's file names and
# product titles. Adapted from gov.usgs.htmc's places.rb, so that both repositories name places alike.
module Places
  US_STATES = {
    'AL' => 'Alabama', 'AK' => 'Alaska', 'AZ' => 'Arizona', 'AR' => 'Arkansas', 'CA' => 'California',
    'CO' => 'Colorado', 'CT' => 'Connecticut', 'DE' => 'Delaware', 'DC' => 'District of Columbia',
    'FL' => 'Florida', 'GA' => 'Georgia', 'HI' => 'Hawaii', 'ID' => 'Idaho', 'IL' => 'Illinois',
    'IN' => 'Indiana', 'IA' => 'Iowa', 'KS' => 'Kansas', 'KY' => 'Kentucky', 'LA' => 'Louisiana',
    'ME' => 'Maine', 'MD' => 'Maryland', 'MA' => 'Massachusetts', 'MI' => 'Michigan', 'MN' => 'Minnesota',
    'MS' => 'Mississippi', 'MO' => 'Missouri', 'MT' => 'Montana', 'NE' => 'Nebraska', 'NV' => 'Nevada',
    'NH' => 'New Hampshire', 'NJ' => 'New Jersey', 'NM' => 'New Mexico', 'NY' => 'New York',
    'NC' => 'North Carolina', 'ND' => 'North Dakota', 'OH' => 'Ohio', 'OK' => 'Oklahoma', 'OR' => 'Oregon',
    'PA' => 'Pennsylvania', 'RI' => 'Rhode Island', 'SC' => 'South Carolina', 'SD' => 'South Dakota',
    'TN' => 'Tennessee', 'TX' => 'Texas', 'UT' => 'Utah', 'VT' => 'Vermont', 'VA' => 'Virginia',
    'WA' => 'Washington', 'WV' => 'West Virginia', 'WI' => 'Wisconsin', 'WY' => 'Wyoming'
  }.freeze

  # Territories and freely associated states, named as gov.usgs.htmc names them. The legacy GNIS state files
  # add the Marshall Islands and the Minor Outlying Islands.
  US_TERRITORIES = {
    'AS' => 'American Samoa', 'FM' => 'Federated States of Micronesia', 'GU' => 'Guam',
    'MH' => 'Marshall Islands', 'MP' => 'Northern Mariana Islands', 'PR' => 'Puerto Rico',
    'PW' => 'Republic of Palau', 'UM' => 'United States Minor Outlying Islands', 'VI' => 'Virgin Islands'
  }.freeze

  # Provinces and states that 1 x 1 degree contour tiles along the borders are filed under
  CANADA = {
    'AB' => 'Alberta', 'BC' => 'British Columbia', 'MB' => 'Manitoba', 'NB' => 'New Brunswick',
    'ON' => 'Ontario', 'QC' => 'Quebec', 'SK' => 'Saskatchewan', 'YT' => 'Yukon'
  }.freeze

  MEXICO = {
    'BCN' => 'Baja California', 'CHH' => 'Chihuahua', 'COA' => 'Coahuila', 'NLE' => 'Nuevo León',
    'SON' => 'Sonora', 'TAM' => 'Tamaulipas'
  }.freeze

  NAMES = US_STATES.merge(US_TERRITORIES, CANADA, MEXICO).freeze
  CODES = NAMES.invert.freeze

  # File names spell some territories other ways
  ALIASES = {
    'Commonwealth of the Northern Mariana Islands' => 'Northern Mariana Islands',
    'North Mariana Islands' => 'Northern Mariana Islands',
    'United States Virgin Islands' => 'Virgin Islands',
    'US Virgin Islands' => 'Virgin Islands',
    'U.S. Virgin Islands' => 'Virgin Islands'
  }.freeze

  # Name for a code, or nil for an unknown code
  def self.name(code)
    NAMES[code.to_s.upcase]
  end

  # Code for a name, e.g. "VI" for "United States Virgin Islands"
  def self.code(name)
    CODES[canonical(name)]
  end

  # The name gov.usgs.htmc uses for a place, given the way a file name or title spells it: "District_of_Columbia"
  # becomes "District of Columbia". Names it doesn't know are returned with their underscores turned to spaces.
  def self.canonical(name)
    spaced = name.to_s.tr('_', ' ').squeeze(' ').strip
    ALIASES.fetch(spaced, spaced)
  end

  # Whether a code is a U.S. state, the District of Columbia, or a territory
  def self.us?(code)
    US_STATES.key?(code) || US_TERRITORIES.key?(code)
  end
end
