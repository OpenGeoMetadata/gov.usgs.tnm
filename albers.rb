# Longitude and latitude of a point in the Albers equal-area grid that S1M's cells are cut from: NAD83(2011)
# Conus Albers (EPSG:6350), whose standard parallels are 29.5°N and 45.5°N, with its origin at 23°N, 96°W. The
# inverse of the projection on the GRS 1980 ellipsoid, after Snyder, Map Projections: A Working Manual (1987),
# equations 3-12, 3-16 and 14-1 to 14-19.
module Albers
  RADIAN = Math::PI / 180
  SEMI_MAJOR_AXIS = 6_378_137.0
  FLATTENING = 1 / 298.257222101
  E2 = FLATTENING * (2 - FLATTENING)
  E = Math.sqrt(E2)

  def self.q(phi)
    sin = Math.sin(phi)
    (1 - E2) * (sin / (1 - E2 * sin**2) - Math.log((1 - E * sin) / (1 + E * sin)) / (2 * E))
  end

  def self.m(phi)
    Math.cos(phi) / Math.sqrt(1 - E2 * Math.sin(phi)**2)
  end

  PHI1 = 29.5 * RADIAN
  PHI2 = 45.5 * RADIAN
  PHI0 = 23.0 * RADIAN
  LAMBDA0 = -96.0 * RADIAN
  N = (m(PHI1)**2 - m(PHI2)**2) / (q(PHI2) - q(PHI1))
  C = m(PHI1)**2 + N * q(PHI1)
  RHO0 = SEMI_MAJOR_AXIS * Math.sqrt(C - N * q(PHI0)) / N

  # @return [Array(Float, Float)] [longitude, latitude] of the point x meters east and y north of the origin
  def self.inverse(x, y)
    rho = Math.sqrt(x**2 + (RHO0 - y)**2)
    theta = Math.atan2(x, RHO0 - y)
    target = (C - (rho * N / SEMI_MAJOR_AXIS)**2) / N
    phi = Math.asin(target / 2)
    # Converges to well under a millimeter in a few steps
    6.times do
      sin = Math.sin(phi)
      phi += (1 - E2 * sin**2)**2 / (2 * Math.cos(phi)) *
             (target / (1 - E2) - sin / (1 - E2 * sin**2) + Math.log((1 - E * sin) / (1 + E * sin)) / (2 * E))
    end
    [(LAMBDA0 + theta / N) / RADIAN, phi / RADIAN]
  end
end
