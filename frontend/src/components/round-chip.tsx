"use client";

import { useConnection, useReadContract } from "wagmi";
import { chain, contracts } from "@/config/contracts";
import {
  demoDriverClockAbi,
  driverVoteAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { Badge } from "@/components/ui/badge";
import { formatCountdown } from "@/lib/countdown";

const chainContracts = contracts[chain.id];

export function RoundChip() {
  const connection = useConnection();
  const onChain = connection.isConnected && connection.chainId === chain.id;
  const round = useReadContract({
    abi: roundScheduleAbi,
    address: chainContracts.roundSchedule,
    chainId: chain.id,
    functionName: "currentRound",
    query: { enabled: onChain },
  });
  const roundEnd = useReadContract({
    abi: driverVoteAbi,
    address: chainContracts.driverVote,
    chainId: chain.id,
    functionName: "openRoundEnd",
    query: { enabled: onChain },
  });
  const clock = useReadContract({
    abi: demoDriverClockAbi,
    address: chainContracts.demoDriverClock,
    chainId: chain.id,
    functionName: "currentTime",
    query: { enabled: onChain },
  });

  if (
    !onChain ||
    round.data === undefined ||
    roundEnd.data === undefined ||
    clock.data === undefined
  ) {
    return null;
  }

  return (
    <div className="flex justify-center">
      <Badge>
        {`Round ${round.data.toString()} · ends in ${formatCountdown(roundEnd.data, clock.data)}`}
      </Badge>
    </div>
  );
}
