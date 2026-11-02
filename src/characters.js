// The creatures: one sculpted body, different ears and default coat. Built entirely in
// code in this repo (MIT), so no third-party model licence applies.
// earDir = right ear direction on the unit sphere; earPower = how narrow (higher = thinner);
// earHeight = how far it sticks out; coat = index into FUR_PRESETS.
export const CHARACTERS = {
  mochi: { name: 'Mochi-Puff', earDir: [0.46, 0.86, 0.06], earPower: 14, earHeight: 0.44, coat: 0 },
  bun: { name: 'Bun', earDir: [0.42, 0.9, -0.02], earPower: 70, earHeight: 1.05, coat: 3 },
  kitty: { name: 'Kitty', earDir: [0.56, 0.82, 0.08], earPower: 28, earHeight: 0.5, coat: 1 },
  cub: { name: 'Cub', earDir: [0.64, 0.76, 0.02], earPower: 44, earHeight: 0.32, coat: 2 },
};

export function currentCharacterKey() {
  const key = new URLSearchParams(location.search).get('character');
  return CHARACTERS[key] ? key : 'mochi';
}
