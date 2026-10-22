"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef } from "react";
import { useBlockNumber } from "wagmi";
import { chain } from "@/config/contracts";

export function useChainBlockRefresh(): void {
  const queryClient = useQueryClient();
  const blockNumber = useBlockNumber({ chainId: chain.id, watch: true });
  const seen = useRef<bigint | undefined>(undefined);

  useEffect(() => {
    if (blockNumber.data === undefined || seen.current === blockNumber.data) {
      return;
    }
    seen.current = blockNumber.data;
    void queryClient.invalidateQueries({ queryKey: ["readContract"] });
    void queryClient.invalidateQueries({ queryKey: ["readContracts"] });
  }, [blockNumber.data, queryClient]);
}
