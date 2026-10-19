"use client";

import {
  useConnection,
  useConnect,
  useConnectors,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { anvil } from "@/config/contracts";
import { walletErrorMessage } from "@/lib/wallet-errors";

export function ConnectWallet() {
  const connection = useConnection();
  const connect = useConnect();
  const connectors = useConnectors();
  const disconnect = useDisconnect();
  const switchChain = useSwitchChain();
  const connector = connectors[0];
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;
  const busy =
    connect.isPending ||
    connection.status === "connecting" ||
    connection.status === "reconnecting" ||
    switchChain.isPending;

  const connectError =
    connect.error === null
      ? undefined
      : walletErrorMessage(connect.error, "connect");
  const switchError =
    switchChain.error === null
      ? undefined
      : walletErrorMessage(switchChain.error, "switch");

  return (
    <>
      <div className="flex flex-wrap gap-2">
        {connection.isConnected ? (
          <button
            type="button"
            className="rounded-md border px-3 py-2 disabled:opacity-50"
            disabled={busy}
            onClick={() => disconnect.mutate()}
          >
            Disconnect
          </button>
        ) : (
          <button
            type="button"
            className="rounded-md border px-3 py-2 disabled:opacity-50"
            disabled={busy || connector === undefined}
            onClick={() => {
              if (connector) {
                connect.mutate({ connector });
              }
            }}
          >
            Connect wallet
          </button>
        )}
        {connection.isConnected && !onAnvil ? (
          <button
            type="button"
            className="rounded-md border px-3 py-2 disabled:opacity-50"
            disabled={busy}
            onClick={() => switchChain.mutate({ chainId: anvil.id })}
          >
            Switch to Anvil
          </button>
        ) : null}
      </div>
      {connectError && !connection.isConnected ? (
        <p role="alert">{connectError}</p>
      ) : null}
      {switchError && connection.isConnected && !onAnvil ? (
        <p role="alert">{switchError}</p>
      ) : null}
    </>
  );
}
