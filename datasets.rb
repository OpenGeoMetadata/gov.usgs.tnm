# The National Map's vector datasets that this repository covers: which of The National Map's dataset tags
# each is listed under, what to call it, The National Map's description of it, and the ArcGIS services that draw it.
module Datasets
  DYNAMIC_MAP_LAYER = 'urn:x-esri:serviceType:ArcGIS#DynamicMapLayer'

  CARTO = 'https://carto.nationalmap.gov/arcgis/rest/services'
  HYDRO = 'https://hydro.nationalmap.gov/arcgis/rest/services'

  # The National Map won't page past about 166,000 products in one query, so a dataset with more is fetched
  # in parts, one query per value of a query parameter
  Dataset = Data.define(:slug, :tags, :name, :keyword, :description, :themes, :resource_types, :services, :url,
                        :partitions)

  # Each description is The National Map's own description of the dataset, word for word, in its paragraphs. It
  # describes NHD, NHDPlus HR and WBD only as what 3DHP replaces, contours only as part of 3DEP, and Combined Vector
  # as the map template that styles it, so they have none here, and their collections take the summary their
  # packages share.
  ALL = [
    Dataset.new(
      slug: 'nbd', tags: ['National Boundary Dataset (NBD)'],
      name: 'USGS National Boundary Dataset (NBD)', keyword: 'National Boundary Dataset',
      description: ['Boundaries data encompasses digital geographic representations of various administrative areas, ' \
                    'including states, counties, cities, towns, federal lands, Native American territories, and ' \
                    'international borders. This governmental unit data supports mapping, visualization, and spatial ' \
                    'analysis in a wide range of applications including resource management, urban planning, ' \
                    'emergency response, environmental conservation, and recreational activities like hiking.'],
      themes: ['Boundaries'], resource_types: ['Polygon data', 'Line data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/govunits/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/4f70b219e4b058caae3f8e19', partitions: nil
    ),
    Dataset.new(
      slug: 'nhd', tags: ['National Hydrography Dataset (NHD) Best Resolution'],
      name: 'USGS National Hydrography Dataset (NHD) Best Resolution', keyword: 'National Hydrography Dataset',
      description: nil,
      themes: ['Inland Waters'], resource_types: ['Line data', 'Polygon data', 'Point data'],
      services: { DYNAMIC_MAP_LAYER => "#{HYDRO}/nhd/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/4f5545cce4b018de15819ca9', partitions: nil
    ),
    Dataset.new(
      slug: 'nhdplushr', tags: ['National Hydrography Dataset Plus High Resolution (NHDPlus HR)'],
      name: 'USGS NHDPlus High Resolution (NHDPlus HR)', keyword: 'NHDPlus High Resolution',
      description: nil,
      themes: ['Inland Waters'], resource_types: ['Line data', 'Polygon data', 'Point data', 'Raster data'],
      services: { DYNAMIC_MAP_LAYER => "#{HYDRO}/NHDPlus_HR/MapServer" },
      url: 'https://www.usgs.gov/3d-hydrography-program', partitions: nil
    ),
    Dataset.new(
      slug: 'wbd', tags: ['National Watershed Boundary Dataset (WBD)'],
      name: 'USGS Watershed Boundary Dataset (WBD)', keyword: 'Watershed Boundary Dataset',
      description: nil,
      themes: ['Inland Waters'], resource_types: ['Polygon data', 'Line data'],
      services: { DYNAMIC_MAP_LAYER => "#{HYDRO}/wbd/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/51361e87e4b03b8ec4025c22', partitions: nil
    ),
    Dataset.new(
      slug: '3dhp', tags: ['3D Hydrography Program (3DHP)'],
      name: 'USGS 3D Hydrography Program (3DHP)', keyword: '3D Hydrography Program',
      description: ['The primary goal of the 3D Hydrography Program (3DHP) is to complete the first systematic ' \
                    'remapping of the Nation’s hydrography since the original 1:24,000-scale topographic mapping ' \
                    'program was active between 1947 and 1992. 3DHP data are being derived from the high-quality ' \
                    'elevation data collected by the 3D Elevation Program (3DEP).',
                    'The 3D Hydrography Program replaces the National Hydrography Dataset (NHD), the Watershed ' \
                    'Boundary Dataset (WBD), and NHDPlus High Resolution (NHDPlus HR) with a single product that ' \
                    'include lakes, streams, catchments, and drainage areas, as well as other hydrologic features. ' \
                    'All of these hydrologic features are derived from 3DEP lidar (IfSAR in Alaska) and validated to ' \
                    'comply with published specifications (Elevation-Derived Hydrography Specifications).'],
      themes: ['Inland Waters'], resource_types: ['Line data', 'Polygon data', 'Point data'],
      services: { DYNAMIC_MAP_LAYER => "#{HYDRO}/3DHP_all/MapServer" },
      url: 'https://www.usgs.gov/3d-hydrography-program', partitions: nil
    ),
    Dataset.new(
      slug: 'mapindices', tags: ['Map Indices'],
      name: 'USGS Map Indices', keyword: 'Map Indices',
      description: ['The map indices (plural of index) are a systematic arrangement designed to help users locate ' \
                    'and access topographic maps produced by the USGS. Most USGS map series divide the United States ' \
                    'into quadrangles bounded by two lines of latitude and two lines of longitude. For example, a ' \
                    '7.5-minute map covers an area that spans 7.5 minutes of latitude and 7.5 minutes of longitude, ' \
                    'and it is typically named after the most prominent feature within the quadrangle. Other maps ' \
                    'may cover a larger area, such as a county, state, national park, or place of special interest. ' \
                    'There are three Map Series quadrangle indices available for download: 7.5-minute ' \
                    '(1:24,000/25,000-scale), 15-minute (1:62,500/63,360-scale), and 1:100,000-scale series.'],
      themes: ['Location'], resource_types: ['Polygon data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/map_indices/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/53d7cd8ee4b06f0f87b7427b', partitions: nil
    ),
    Dataset.new(
      slug: 'gnis', tags: ['National Geographic Names Information System (GNIS)'],
      name: 'USGS Geographic Names Information System (GNIS)', keyword: 'Geographic Names Information System',
      description: ['Place names within the United States and its dependent areas are recorded and available in the ' \
                    'Geographic Names Information System (GNIS). It is the responsibility of the Domestic Names ' \
                    'Committee (DNC) of the U.S. Board on Geographic Names (BGN) to maintain this system. GNIS is ' \
                    'the federal and national standard for geographic names and serves as the official geographic ' \
                    'names source for all federal departments and federal digital and printed products.'],
      themes: ['Location'], resource_types: ['Point data', 'Table data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/geonames/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/4f70b292e4b058caae3f8e1d', partitions: nil
    ),
    Dataset.new(
      slug: 'smallscale',
      tags: ['Small-scale Datasets - Boundaries', 'Small-scale Datasets - Contours', 'Small-scale Datasets - Hydrography',
             'Small-scale Datasets - Transportation'],
      name: 'USGS Small-scale Datasets', keyword: 'Small-scale Datasets',
      description: ['Small-scale datasets consist of 1:1,000,000-scale contours, hydrography, transportation, and ' \
                    'boundaries data that were originally developed for the 1997-2014 Edition of the National Atlas ' \
                    'of the United States. In general, some details of features found in data intended for ' \
                    'large-scale maps are limited or omitted in small-scale data. These datasets are not regularly ' \
                    'updated have not been refreshed since they were retired in September 2014.'],
      themes: ['Boundaries', 'Elevation', 'Inland Waters', 'Transportation'],
      resource_types: ['Line data', 'Polygon data', 'Point data'], services: {},
      url: 'https://www.sciencebase.gov/catalog/item/532c5b23e4b0cd7393d07783', partitions: nil
    ),
    Dataset.new(
      slug: 'nsd', tags: ['National Structures Dataset (NSD)'],
      name: 'USGS National Structures Dataset (NSD)', keyword: 'National Structures Dataset',
      description: ['USGS Structures data provides information on manmade facilities across the United States and ' \
                    'its territories, including the point locations, functionalities, names, precise geographic ' \
                    'coordinates, and other relevant details of these structures. Covering a wide range of structure ' \
                    'types, from emergency services to recreational facilities, this data serves multiple purposes ' \
                    'beyond its original focus on emergency management. It is a valuable resource for urban ' \
                    'planning, infrastructure development, and various industries that utilize geographic ' \
                    'information systems for analysis and decision-making.'],
      themes: ['Structure'], resource_types: ['Point data', 'Polygon data', 'Line data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/structures/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/4f70b240e4b058caae3f8e1b', partitions: nil
    ),
    Dataset.new(
      slug: 'ntd', tags: ['National Transportation Dataset (NTD)'],
      name: 'USGS National Transportation Dataset (NTD)', keyword: 'National Transportation Dataset',
      description: ['USGS Transportation data is a network of geospatially referenced features including roads, ' \
                    'trails, airports, and railroads across the United States and its territories. This dataset ' \
                    'provides detailed information on the location, classification, and identification of ' \
                    'transportation infrastructure, supporting cartographic representation and facilitating ' \
                    'geographic analysis. This comprehensive view of national transportation networks aids in ' \
                    'infrastructure development and public safety initiatives, enabling informed decision-making by ' \
                    'planners, emergency services, and government agencies.'],
      themes: ['Transportation'], resource_types: ['Line data', 'Point data', 'Polygon data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/transportation/MapServer" },
      url: 'https://www.sciencebase.gov/catalog/item/4f70b1f4e4b058caae3f8e16', partitions: nil
    ),
    # The National Map has no service of its own for woodland tint; the USGS Topo basemap draws it among
    # everything else, which would misrepresent the package
    Dataset.new(
      slug: 'woodland', tags: ['Land Cover - Woodland'],
      name: 'USGS Woodland Tint', keyword: 'Woodland Tint',
      description: ['This general purpose dataset illustrates woodland areas on the Earth\'s surface. The geospatial ' \
                    'data in this file are derived from selected National Map data and other government sources, ' \
                    'including the National Land Cover Database (NLCD).'],
      themes: ['Land Cover'], resource_types: ['Polygon data'], services: {},
      url: 'https://www.sciencebase.gov/catalog/item/5318a64ee4b051b1b924ea2c', partitions: nil
    ),
    Dataset.new(
      slug: 'contours', tags: ['National Elevation Dataset (NED) 1/3 arc-second - Contours'],
      name: 'USGS 1/3 Arc-Second Contours', keyword: 'Contours',
      description: nil,
      themes: ['Elevation'], resource_types: ['Line data'],
      services: { DYNAMIC_MAP_LAYER => "#{CARTO}/contours/MapServer" },
      url: 'https://www.usgs.gov/3d-elevation-program/about-3dep-products-services', partitions: nil
    ),
    # Combined Vector packages get no service references: their data comes from every other dataset here, so no
    # one service draws them
    Dataset.new(
      slug: 'vector', tags: ['Combined Vector'],
      name: 'USGS Topo Map Vector Data', keyword: 'Topo Map Vector Data',
      description: nil,
      themes: ['Boundaries', 'Elevation', 'Inland Waters', 'Land Cover', 'Location', 'Structure', 'Transportation'],
      resource_types: ['Line data', 'Polygon data', 'Point data'], services: {},
      url: 'https://www.sciencebase.gov/catalog/item/5135fc88e4b03b8ec4025bc9',
      partitions: { 'prodFormats' => ['FileGDB', 'FileGDB 10.1', 'Shapefile', 'GeoPackage'] }
    )
  ].freeze

  BY_SLUG = ALL.to_h { |dataset| [dataset.slug, dataset] }.freeze
  BY_TAG = ALL.flat_map { |dataset| dataset.tags.map { |tag| [tag, dataset] } }.to_h.freeze

  # Small-scale packages are themed by the tag they're listed under
  SMALL_SCALE_THEMES = {
    'Small-scale Datasets - Boundaries' => ['Boundaries'], 'Small-scale Datasets - Contours' => ['Elevation'],
    'Small-scale Datasets - Hydrography' => ['Inland Waters'],
    'Small-scale Datasets - Transportation' => ['Transportation']
  }.freeze

  def self.fetch(slug)
    BY_SLUG.fetch(slug)
  end

  def self.for_tag(tag)
    BY_TAG[tag]
  end
end
