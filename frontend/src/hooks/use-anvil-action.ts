"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import type {
  Abi,
  Address,
  ContractFunctionArgs,
  ContractFunctionName,
  Hex,
} from "viem";
import {
  useConfig,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { simulateContract } from "wagmi/actions";
import { anvil } from "@/config/contracts";

export function useAnvilAction<
  const abi extends Abi,
  functionName extends ContractFunctionName<abi, "nonpayable" | "payable">,
>(options: {
  scope: string;
  account: Address | undefined;
  abi: abi;
  address: Address;
  functionName: functionName;
  args?: ContractFunctionArgs<abi, "nonpayable" | "payable", functionName>;
  describeError: (error: unknown) => string;
  describeReceiptError: (error: unknown) => string;
}) {
  const config = useConfig();
  const queryClient = useQueryClient();
  const [scope, setScope] = useState(options.scope);
  const [simulating, setSimulating] = useState(false);
  const [simulationError, setSimulationError] = useState<string>();
  const scopeRef = useRef(options.scope);
  const refreshedHash = useRef<Hex | undefined>(undefined);
  const write = useWriteContract();

  if (scope !== options.scope) {
    setScope(options.scope);
    setSimulating(false);
    setSimulationError(undefined);
    write.reset();
  }

  useEffect(() => {
    scopeRef.current = options.scope;
  }, [options.scope]);

  const receipt = useWaitForTransactionReceipt({
    chainId: anvil.id,
    hash: write.data,
  });

  useEffect(() => {
    if (
      !receipt.isSuccess ||
      write.data === undefined ||
      refreshedHash.current === write.data
    ) {
      return;
    }
    refreshedHash.current = write.data;
    void queryClient.invalidateQueries({ queryKey: ["readContract"] });
  }, [queryClient, receipt.isSuccess, write.data]);

  const confirming =
    write.data !== undefined && !receipt.isSuccess && !receipt.isError;
  const busy = simulating || write.isPending || confirming;
  const errorMessage =
    write.data !== undefined && receipt.isError
      ? options.describeReceiptError(receipt.error)
      : write.error
        ? options.describeError(write.error)
        : simulationError;

  async function send(): Promise<void> {
    if (options.account === undefined) {
      return;
    }
    const started = scopeRef.current;
    write.reset();
    setSimulationError(undefined);
    setSimulating(true);
    const args = options.args;
    const call = {
      abi: options.abi,
      account: options.account,
      address: options.address,
      chainId: anvil.id,
      functionName: options.functionName,
      ...(args === undefined ? {} : { args }),
    };
    try {
      await simulateContract(
        config,
        call as unknown as Parameters<typeof simulateContract>[1],
      );
    } catch (error) {
      if (scopeRef.current === started) {
        setSimulationError(options.describeError(error));
        setSimulating(false);
      }
      return;
    }
    if (scopeRef.current !== started) {
      return;
    }
    setSimulating(false);
    write.mutate(call as unknown as Parameters<typeof write.mutate>[0]);
  }

  return {
    send,
    simulating,
    writePending: write.isPending,
    confirming,
    busy,
    errorMessage,
    isSuccess: receipt.isSuccess,
    receipt,
  };
}
