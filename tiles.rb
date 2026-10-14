require_relative 'albers'

# The grids 3DEP's seamless DEMs are cut by. The arc-second DEMs are tiled by degrees of latitude and longitude,
# and S1M by 10-kilometer cells of an Albers grid, whose edges aren't parallels and meridians.
module Tiles
  CELL = 10_000

  # [west, east, north, south] of a 1 x 1 degree tile, which is named for its north-west corner: n42w092 covers
  # 41°N to 42°N and 92°W to 91°W
  def self.degree_box(name)
    north = name[1, 2].to_i * (name[0] == 'n' ? 1 : -1)
    west = name[4, 3].to_i * (name[3] == 'e' ? 1 : -1)
    [west, west + 1, north, north - 1]
  end

  # [longitude, latitude] of an S1M cell's corners, counterclockwise from its south-west corner. A cell is named
  # for its upper-left corner, in kilometers east and north of the grid's origin: n0450e1510 runs from 1,510 to
  # 1,520 kilometers east, and 440 to 450 north.
  def self.cell_corners(name)
    north = name[1, 4].to_i * 1000 * (name[0] == 'n' ? 1 : -1)
    west = name[6, 4].to_i * 1000 * (name[5] == 'e' ? 1 : -1)
    [[west, north - CELL], [west + CELL, north - CELL], [west + CELL, north], [west, north]]
      .map { |x, y| Albers.inverse(x, y) }
  end

  # e.g. "41°–42°N, 91°–92°W" for n42w092
  def self.degree_label(name)
    west, east, north, south = degree_box(name)
    "#{span(south, north, 'N', 'S')}, #{span(west, east, 'E', 'W')}"
  end

  # e.g. "25.97°N, 80.95°W", the middle of cell n0450e1510
  def self.cell_label(name)
    longitude, latitude = cell_corners(name).transpose.map { |values| values.sum / values.size }
    "#{format('%.2f', latitude.abs)}°#{latitude.negative? ? 'S' : 'N'}, " \
      "#{format('%.2f', longitude.abs)}°#{longitude.negative? ? 'W' : 'E'}"
  end

  # Degrees from low to high, named by their hemisphere: "41°–42°N", "91°–92°W"
  def self.span(low, high, positive, negative)
    if low >= 0 then "#{low}°–#{high}°#{positive}"
    elsif high <= 0 then "#{-high}°–#{-low}°#{negative}"
    else "#{-low}°#{negative}–#{high}°#{positive}"
    end
  end
end
