require 'minitest/autorun'
require_relative '../extents'

class ExtentsTest < Minitest::Test
  # The catalog's box for Alaska, whose western Aleutians are past the antimeridian
  ALASKA = [-179.23109, 179.85968, 71.43979, 51.17509].freeze
  IOWA = [-96.63949, -90.14006, 43.5012, 40.37544].freeze

  def package(slug, unit, bounds)
    Package.new(Datasets.fetch(slug), unit).tap { |package| package.bounds = bounds }
  end

  def test_a_box_around_the_antimeridian_circles_the_globe_but_one_reaching_a_pole_does_not
    assert Extents.circles_globe?(ALASKA)
    refute Extents.circles_globe?(IOWA)
    refute Extents.circles_globe?([-180.0, 179.9999, -42.5162, -90.0]), 'Antarctica spans every longitude'
    refute Extents.circles_globe?([172.3478, -129.9742, 71.4398, 51.1751]), 'a box crossing the antimeridian'
  end

  def test_packages_are_keyed_by_the_state_or_hydrologic_unit_they_cover
    assert_equal 'AK', Extents.area(package('nbd', { kind: :state, state: 'Alaska' }, ALASKA))
    assert_equal 'AK', Extents.area(package('3dhp', { kind: :edition, area: 'Alaska', date: '20250313' }, ALASKA))
    assert_equal 'AK', Extents.area(package('gnis', { kind: :names, series: 'FedCodes', code: 'AK' }, ALASKA))
    assert_equal '19030103', Extents.area(package('nhd', { kind: :hydrologic_unit, code: '19030103' }, ALASKA))
    assert_nil Extents.area(package('gnis', { kind: :names, series: 'FedCodes', code: 'AllStates' }, ALASKA))
  end

  # Alaska's box comes from data/extents.json, and the national package's from its dataset's other packages
  def test_boxes_that_circle_the_globe_are_replaced
    alaska = package('nbd', { kind: :state, state: 'Alaska' }, ALASKA)
    iowa = package('nbd', { kind: :state, state: 'Iowa' }, IOWA)
    national = package('nbd', { kind: :national }, [-179.23109, 179.85968, 71.43979, -14.60181])
    left = Extents.correct([national, alaska, iowa])

    assert_empty left
    assert_equal Extents.boxes.fetch('AK'), alaska.bounds
    measured = Extents.boxes.fetch('AK')
    assert_equal [measured[0], IOWA[1], measured[2], IOWA[3]], national.bounds
    assert_equal IOWA, iowa.bounds
  end

  def test_boxes_with_nothing_better_are_left_and_returned
    unknown = package('nhd', { kind: :hydrologic_unit, code: '99999999' }, ALASKA)

    assert_equal [unknown], Extents.correct([unknown])
    assert_equal ALASKA, unknown.bounds
  end

  # ArcGIS splits a boundary at the antimeridian, so its rings are on one side or the other
  def test_a_boundary_on_both_sides_of_the_antimeridian_is_measured_across_it
    rings = [[[172.4, 52.9], [173.6, 52.7], [172.4, 52.4], [172.4, 52.9]],
             [[-170.3, 52.6], [-169.6, 52.9], [-170.3, 53.1], [-170.3, 52.6]]]

    assert_equal [172.4, -169.6, 53.1, 52.4], Extents.measure(rings)
  end

  def test_an_extent_counts_a_box_crossing_the_antimeridian_as_its_two_halves
    extent = Extent.new
    extent.add(172.0, -130.0, 71.0, 51.0)
    extent.add(-96.6, -90.1, 43.5, 40.4)

    assert_equal [172.0, -90.1], extent.longitudes
  end
end
