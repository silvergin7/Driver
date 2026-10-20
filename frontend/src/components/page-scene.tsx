type ScenePage = "home" | "game" | "token" | "community" | "faucet" | "swap";

export function PageScene({ page }: { page: ScenePage }) {
  return (
    <div
      aria-hidden="true"
      className={`scene scene-${page} relative aspect-[3/1] w-full max-h-[32rem]`}
    >
      <div className="pointer-events-none absolute inset-x-0 bottom-0 h-1/8 bg-gradient-to-b from-transparent to-background" />
    </div>
  );
}
