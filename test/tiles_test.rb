require 'minitest/autorun'
require_relative '../tiles'

class TilesTest < Minitest::Test
  # A tile is named for its north-west corner
  def test_a_degree_tile_covers_the_degree_south_east_of_its_name
    assert_equal [-92, -91, 42, 41], Tiles.degree_box('n42w092')
    assert_equal [162, 163, 6, 5], Tiles.degree_box('n06e162')
    assert_equal [-171, -170, -14, -15], Tiles.degree_box('s14w171')
  end

  def test_degree_tiles_are_labelled_by_their_latitudes_and_longitudes
    assert_equal '41°–42°N, 91°–92°W', Tiles.degree_label('n42w092')
    assert_equal '5°–6°N, 162°–163°E', Tiles.degree_label('n06e162')
    assert_equal '14°–15°S, 170°–171°W', Tiles.degree_label('s14w171')
    assert_equal '0°–1°N, 0°–1°E', Tiles.degree_label('n01e000')
  end

  # The catalog's box for cell n0450e1510, off the coast of Florida, is the envelope of these corners
  def test_an_s1m_cell_is_the_10_kilometers_east_and_south_of_its_name
    corners = Tiles.cell_corners('n0450e1510')
    longitudes, latitudes = corners.transpose

    assert_in_delta(-81.0028601420002, longitudes.min, 1e-6)
    assert_in_delta(-80.8895404313893, longitudes.max, 1e-6)
    assert_in_delta(25.92070859857935, latitudes.min, 1e-6)
    assert_in_delta(26.025030076412904, latitudes.max, 1e-6)
    assert_equal '25.97°N, 80.95°W', Tiles.cell_label('n0450e1510')
  end

  def test_the_albers_grids_origin_is_at_23_north_96_west
    longitude, latitude = Albers.inverse(0, 0)

    assert_in_delta(-96, longitude, 1e-9)
    assert_in_delta(23, latitude, 1e-9)
  end
end
