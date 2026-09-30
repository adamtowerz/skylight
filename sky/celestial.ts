/**
 * Where the sun, moon and stars are. A fixed latitude and declination give a believable
 * summer arc; the hour angle turns the whole celestial sphere about the pole.
 * Local frame: x = east, y = up, z = north.
 */

import { add, basisMatrix, cross, dot, radians, scale, type Mat4, type Vec3 } from './math'

const latitude = radians(40)
const sunDeclination = radians(15)
/**
 * The sun's right ascension at that declination in mid-August, so evenings have the real summer
 * sky: Vega near the zenith, Arcturus in the west, the Milky Way overhead through Cygnus.
 */
const sunRightAscension = radians(141.8)
/** A waxing gibbous moon trailing the sun, so evenings get moonlight. */
const moonHourOffset = radians(-150)
const moonDeclination = radians(5)

/**
 * Full-moon light: faint and silvery. Amplified far beyond reality so night reads, but less than
 * the airglow (`nightGlow`), which shines from above the clouds: so moonlit clouds stand dark
 * against the deep blue, with silver only where they are thin and near the moon.
 */
const fullMoonIlluminance: Vec3 = [0.015, 0.017, 0.021]

const pole: Vec3 = [0, Math.sin(latitude), Math.cos(latitude)]
/** Where the celestial equator crosses the meridian: due south. */
const meridian: Vec3 = [0, Math.cos(latitude), -Math.sin(latitude)]
const east: Vec3 = [1, 0, 0]

/** Point on the celestial equator at hour angle `h` (0 = on the meridian, positive = west). */
const equator = (h: number) => add(scale(meridian, Math.cos(h)), scale(east, -Math.sin(h)))

const onSphere = (h: number, declination: number) =>
  add(scale(equator(h), Math.cos(declination)), scale(pole, Math.sin(declination)))

/** Solar hour angle: 0 at noon, one full turn per day. */
const hourAngle = (hour: number) => ((hour - 12) / 12) * Math.PI

const sunDirection = (hour: number) => onSphere(hourAngle(hour), sunDeclination)

/** Sun elevation above the horizon, in radians. */
export const sunElevation = (hour: number) => Math.asin(sunDirection(hour)[1])

export interface Celestial {
  sunDirection: Vec3
  moonDirection: Vec3
  moonIlluminance: Vec3
  /**
   * Columns are the J2000 equatorial basis (x toward RA 0h, y toward 6h, z the pole) in local
   * coordinates, so the stars turn with the Earth.
   */
  skyRotation: Mat4
}

export function celestial(hour: number): Celestial {
  const h = hourAngle(hour)
  const sun = onSphere(h, sunDeclination)
  const moon = onSphere(h + moonHourOffset, moonDeclination)
  const illuminatedFraction = (1 - dot(sun, moon)) / 2
  // Local sidereal time is the hour angle of RA 0h; RA 6h lies east of it, x × pole here.
  const x = equator(h + sunRightAscension)
  return {
    sunDirection: sun,
    moonDirection: moon,
    moonIlluminance: scale(fullMoonIlluminance, illuminatedFraction),
    skyRotation: basisMatrix(x, cross(x, pole), pole),
  }
}
