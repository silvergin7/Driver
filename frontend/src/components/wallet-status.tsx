"use client";

import { useConnection, useConnect } from "wagmi";
import { anvil } from "@/config/contracts";
import { ConnectWallet } from "@/components/connect-wallet";
import { sectionClass } from "@/lib/control-class";

export function WalletStatus() {
  const connection = useConnection();
  const connect = useConnect();
  const onAnvil = connection.isConnected && connection.chainId === anvil.id;

  return (
    <section className={sectionClass()}>
      <p>
        {connection.status === "connecting" || connect.isPending
          ? "Connecting…"
          : connection.status === "reconnecting"
            ? "Reconnecting…"
            : connection.isConnected
              ? onAnvil
                ? "Connected."
                : "Wrong network."
              : "Not connected."}
      </p>
      {connection.isConnected && connection.address ? (
        <p className="break-all font-mono text-sm">{connection.address}</p>
      ) : null}
      <ConnectWallet />
    </section>
  );
}
