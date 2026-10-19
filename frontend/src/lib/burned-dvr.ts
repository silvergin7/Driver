export function burnedDvr(minted: bigint, supply: bigint): bigint | undefined {
  if (supply > minted) {
    return undefined;
  }
  return minted - supply;
}
