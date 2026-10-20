export function farmAprBps(input: {
  aprBps: bigint;
  active: boolean;
  paused: boolean;
  rewardReserve: bigint;
}): bigint {
  if (!input.active || input.paused || input.rewardReserve === 0n) {
    return 0n;
  }
  return input.aprBps;
}
