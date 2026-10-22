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
import { chain } from "@/config/contracts";

export function useChainAction<
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
  const waiter = useRef<{ resolve: (ok: boolean) => void } | undefined>(
    undefined,
  );
  const write = useWriteContract();

  function finish(ok: boolean): void {
    const current = waiter.current;
    if (current === undefined) {
      return;
    }
    waiter.current = undefined;
    current.resolve(ok);
  }

  if (scope !== options.scope) {
    setScope(options.scope);
    setSimulating(false);
    setSimulationError(undefined);
    write.reset();
  }

  useEffect(() => {
    scopeRef.current = options.scope;
    finish(false);
  }, [options.scope]);

  const receipt = useWaitForTransactionReceipt({
    chainId: chain.id,
    hash: write.data,
  });

  useEffect(() => {
    if (write.error) {
      finish(false);
      return;
    }
    if (write.data === undefined) {
      return;
    }
    if (receipt.isSuccess) {
      if (refreshedHash.current !== write.data) {
        refreshedHash.current = write.data;
        void queryClient.invalidateQueries({ queryKey: ["readContract"] });
      }
      finish(true);
      return;
    }
    if (receipt.isError) {
      finish(false);
    }
  }, [queryClient, receipt.isError, receipt.isSuccess, write.data, write.error]);

  const confirming =
    write.data !== undefined && !receipt.isSuccess && !receipt.isError;
  const busy = simulating || write.isPending || confirming;
  const errorMessage =
    write.data !== undefined && receipt.isError
      ? options.describeReceiptError(receipt.error)
      : write.error
        ? options.describeError(write.error)
        : simulationError;

  async function send(
    override?: ContractFunctionArgs<abi, "nonpayable" | "payable", functionName>,
  ): Promise<boolean> {
    if (options.account === undefined) {
      return false;
    }
    const started = scopeRef.current;
    finish(false);
    write.reset();
    setSimulationError(undefined);
    setSimulating(true);
    const args = override === undefined ? options.args : override;
    const call = {
      abi: options.abi,
      account: options.account,
      address: options.address,
      chainId: chain.id,
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
      return false;
    }
    if (scopeRef.current !== started) {
      return false;
    }
    setSimulating(false);
    return await new Promise<boolean>((resolve) => {
      waiter.current = { resolve };
      write.mutate(call as unknown as Parameters<typeof write.mutate>[0]);
    });
  }

  return {
    send,
    simulating,
    writePending: write.isPending,
    confirming,
    busy,
    errorMessage,
    hash: write.data,
    isSuccess: receipt.isSuccess,
    receipt,
  };
}
