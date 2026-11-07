import { PageScene } from "@/components/page-scene";
import { RoadSign } from "@/components/road-sign";

const stops = [
  { text: "Theory test passed (contracts tested and reviewed).", done: true },
  { text: "Practice laps (the Sepolia demo, v0.1.0).", done: true },
  { text: "First lesson on the open road (Ethereum mainnet, v0.2.0).", done: true },
  { text: "Driving test (the first harvest on mainnet).", done: false },
  { text: "Driving licence (ambassador NFT).", done: false },
  { text: "A licence for the highway too (Fund 3), if the instructors agree.", done: false },
  { text: "Real fuel in the tank (real USDC, after an outside audit).", done: false },
];

export default function CommunityPage() {
  return (
    <>
      <PageScene page="community" />
      <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-12 px-6 pt-8 pb-12">
        <section className="flex max-w-3xl flex-col gap-4">
          <h1 className="text-4xl font-semibold tracking-tight text-brand-text">Community</h1>
          <p className="text-lg text-ink">
            Driver is the driving school where the treasury is the student driver and
            the DVR holders are the instructors. Cruise Control is the careful student
            who never goes above 5%. Degen Driver is the one who wants to try every
            speed, so the instructors vote each month on how fast it&apos;s allowed to
            drive. Once a month the harvest is the driving test: what the car earned
            gets refuelled, and the rest burns DVR.
          </p>
        </section>
        <section className="flex flex-col gap-4">
          <h2 className="text-2xl font-semibold text-ink">Roadmap</h2>
          <div aria-hidden="true" className="border-t-2 border-dashed border-line" />
          <ol className="flex max-w-xl flex-col gap-4 border-l-2 border-dashed border-line pl-6">
            {stops.map((stop, index) => (
              <RoadSign key={stop.text} marker={String(index + 1)} done={stop.done}>
                {stop.text}
              </RoadSign>
            ))}
          </ol>
        </section>
      </main>
    </>
  );
}
