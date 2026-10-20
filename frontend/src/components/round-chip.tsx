"use client";

import { useConnection, useReadContract } from "wagmi";
import { anvil, contracts } from "@/config/contracts";
import {
  demoDriverClockAbi,
  driverVoteAbi,
  roundScheduleAbi,
} from "@/generated/contracts";
import { Badge } from "@/components/ui/badge";
import { formatCountdown } from "@/lib/countdown";

const anvilContracts = contracts[anvil.id];

export function RoundChip() {
  const connection = useConnection();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const round = useReadContract({
    abi: roundScheduleAbi,
    address: anvilContracts.roundSchedule,
    chainId: anvil.id,
    functionName: "currentRound",
    query: { enabled: onAnvil },
  });
  const roundEnd = useReadContract({
    abi: driverVoteAbi,
    address: anvilContracts.driverVote,
    chainId: anvil.id,
    functionName: "openRoundEnd",
    query: { enabled: onAnvil },
  });
  const clock = useReadContract({
    abi: demoDriverClockAbi,
    address: anvilContracts.demoDriverClock,
    chainId: anvil.id,
    functionName: "currentTime",
    query: { enabled: onAnvil },
  });

  if (
    !onAnvil ||
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
