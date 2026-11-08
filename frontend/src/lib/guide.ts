export const loopTitle = "The loop in short";

export const loopSteps = [
  { word: "Claim", hint: "free tokens" },
  { word: "Swap", hint: "1% tax" },
  { word: "Lock", hint: "your DVR" },
  { word: "Vote", hint: "farm speed" },
  { word: "Farm", hint: "earn yield" },
  { word: "Harvest", hint: "monthly" },
  { word: "Burn", hint: "fewer DVR" },
  { word: "Top-up", hint: "safe fund" },
  { word: "Repeat", hint: "next month" },
] as const;

export const pictureTitle = "How Driver works, in pictures";

export const pictureSteps = [
  {
    id: "guide-1-claim",
    title: "Fill up for free",
    alt: "A white car parks under a big tap that drops gold DVR coins and blue mUSDC coins into its roof. An hourglass floats beside it.",
    caption:
      "The faucets give you 10 DVR and 100 mUSDC, once every 24 hours. mUSDC is play money that stands in for real USDC.",
  },
  {
    id: "guide-2-swap",
    title: "Trade in the pool",
    alt: "A white car drives round a roundabout with a seesaw of gold and blue coins in the middle. A toll booth at the exit sends a small coin down two pipes, to a blue garage and a red garage.",
    caption:
      "Swap mUSDC for DVR, or back. Every swap pays a 1% toll in mUSDC. Each fund gets 40% of the toll, and the last 20% is kept for a future third fund.",
  },
  {
    id: "guide-3-lock-vote",
    title: "Lock and vote",
    alt: "A locked treasure chest full of gold coins. Next to it, white cars face three speed signs, 40, 80 and 160, and a ballot goes into a box.",
    caption:
      "Lock DVR to become an instructor. Then vote on how fast Degen Driver may drive this month: Highway (40%), Autobahn (80%) or Drift (160%).",
  },
  {
    id: "guide-4-month",
    title: "A month goes by",
    alt: "The sun and moon cross the sky. The blue car cruises past a farm with a small stack of coins. Below, the red car speeds down a highway with a taller stack.",
    caption:
      "Cruise Control drives safely and earns 5% a year. Degen Driver drives at the speed the vote picked, so it can earn more.",
  },
  {
    id: "guide-5-harvest",
    title: "Harvest day",
    alt: "A pile of blue reward coins splits in two. One half refuels the red and blue cars. The other half becomes gold coins that burn in a fire bin.",
    caption:
      "Each fund collects what it earned. Half goes back into the fund. The other half buys DVR from the pool and burns it, so fewer DVR exist.",
  },
  {
    id: "guide-6-top-up",
    title: "Keeping the safe fund strong",
    alt: "A tired blue car with a low fuel gauge gets a top-up through a hose from the energetic red car.",
    caption:
      "If Cruise Control drops below three quarters of the two funds together, Degen Driver tops it up at the end of its harvest. Then the loop starts again.",
  },
] as const;

export const glossaryTitle = "Words to know";

export const glossary = [
  {
    term: "Smart contract",
    definition:
      "A program that lives on Ethereum. It runs exactly as written, and anyone can read its code.",
  },
  {
    term: "Wallet",
    definition:
      "An app, like MetaMask, that holds your tokens and approves your actions. Only you control it.",
  },
  {
    term: "ETH and gas",
    definition:
      "ETH is Ethereum's own coin. Every action on Ethereum costs a small fee in ETH, called gas. On this site, gas is the only real money.",
  },
  {
    term: "Mainnet and testnet",
    definition:
      "Mainnet is the real Ethereum network. A testnet, like Sepolia, is a practice copy where everything is free.",
  },
  {
    term: "Token",
    definition: "A digital coin made by a smart contract. Driver has two: DVR and mUSDC.",
  },
  {
    term: "DVR",
    definition:
      "Driver's own token. There will never be more than 1,000,000. Holders can lock it to vote.",
  },
  {
    term: "mUSDC",
    definition:
      "Play money that stands in for USDC, a coin worth one US dollar. Here it has no value.",
  },
  {
    term: "Faucet",
    definition: "A tap that hands out free tokens. You can claim from each one once every 24 hours.",
  },
  {
    term: "Pool",
    definition:
      "A shared pot of DVR and mUSDC that anyone can trade with. The mix in the pot sets the price.",
  },
  {
    term: "Swap",
    definition: "Trading one token for the other in the pool.",
  },
  {
    term: "Price",
    definition:
      "How many mUSDC one DVR costs right now. Buying DVR pushes the price up. Selling pushes it down.",
  },
  {
    term: "Slippage",
    definition:
      "How much the price may move between your click and the trade. The site lets you set a limit.",
  },
  {
    term: "Tax",
    definition: "A 1% fee on every swap, paid in mUSDC. It goes to the funds, not to a person.",
  },
  {
    term: "Treasury fund",
    definition: "A pot of mUSDC that works for the project. Driver has two.",
  },
  {
    term: "Cruise Control",
    definition: "The careful fund. It always uses a safe farm that pays 5% a year.",
  },
  {
    term: "Degen Driver",
    definition: "The bold fund. Every month, the DVR holders vote on how fast its farm may go.",
  },
  {
    term: "Yield farm",
    definition:
      "A place where a fund parks money to earn more. Here the farms are pretend, and they can't lose the money put in.",
  },
  {
    term: "APR",
    definition:
      "What a farm pays over a full year, as a percentage. 5% APR on 100 mUSDC is about 5 mUSDC a year.",
  },
  {
    term: "Lock",
    definition:
      "Putting DVR aside so it counts as votes. You can unlock it, but not while your vote in the current round is still open.",
  },
  {
    term: "Round",
    definition: "One month of voting. When it ends, the harvest uses the winning speed.",
  },
  {
    term: "Harvest",
    definition: "Once a month, each fund collects what its farm earned.",
  },
  {
    term: "Compounding",
    definition: "Putting earnings back in, so next time you earn on a bigger amount.",
  },
  {
    term: "Buyback and burn",
    definition:
      "The fund buys DVR from the pool and destroys it. That leaves fewer DVR in the world.",
  },
  {
    term: "Total supply",
    definition: "How many DVR exist right now. Every burn makes it smaller.",
  },
  {
    term: "Top-up",
    definition:
      "If the careful fund gets too small next to the bold one, the bold fund passes money back to it.",
  },
  {
    term: "Demo clock",
    definition:
      "The project's own clock. The owner can move it a month forward, so a harvest can be shown without waiting. It never goes back.",
  },
  {
    term: "Simulation",
    definition:
      "This page. It replays the real contracts on a computer, so you can see the whole loop for free. Nothing here is on-chain.",
  },
  {
    term: "Etherscan",
    definition: "A website where anyone can look up any transaction or contract on Ethereum.",
  },
] as const;

export function guideImageSrc(id: string, theme: "day" | "night", width: 768 | 1440): string {
  return `/guide/${id}-${theme}-${width}.webp`;
}
