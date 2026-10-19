"use client";

import {
  useConnection,
  useConnect,
  useConnectors,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { anvil } from "@/config/contracts";
import { actionButtonClass } from "@/lib/control-class";
import { walletAlertText } from "@/lib/wallet-alert";
import { walletErrorMessage } from "@/lib/wallet-errors";

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function useWalletControls() {
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
  const alertMessage = walletAlertText(
    connectError,
    switchError,
    connection.isConnected,
    onAnvil,
  );

  return {
    connection,
    connector,
    connect,
    disconnect,
    switchChain,
    busy,
    onAnvil,
    alertMessage,
    connectError,
    switchError,
  };
}

type WalletControls = ReturnType<typeof useWalletControls>;

export function ConnectWallet({
  compact = false,
  showAlert = true,
  controls,
}: {
  compact?: boolean;
  showAlert?: boolean;
  controls?: WalletControls;
}) {
  if (controls !== undefined) {
    return (
      <WalletMarkup controls={controls} compact={compact} showAlert={showAlert} />
    );
  }
  return <OwnWallet compact={compact} showAlert={showAlert} />;
}

function OwnWallet({
  compact,
  showAlert,
}: {
  compact: boolean;
  showAlert: boolean;
}) {
  const controls = useWalletControls();
  return (
    <WalletMarkup controls={controls} compact={compact} showAlert={showAlert} />
  );
}

function WalletMarkup({
  controls,
  compact,
  showAlert,
}: {
  controls: WalletControls;
  compact: boolean;
  showAlert: boolean;
}) {
  const {
    connection,
    connector,
    connect,
    disconnect,
    switchChain,
    busy,
    onAnvil,
    alertMessage,
    connectError,
    switchError,
  } = controls;

  if (compact) {
    return (
      <div className="flex flex-col items-start gap-2">
        {!connection.isConnected ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy || connector === undefined}
            onClick={() => {
              if (connector) {
                connect.mutate({ connector });
              }
            }}
          >
            Connect wallet
          </button>
        ) : !onAnvil ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy}
            onClick={() => switchChain.mutate({ chainId: anvil.id })}
          >
            Switch to Anvil
          </button>
        ) : connection.address !== undefined ? (
          <p className="whitespace-nowrap font-mono text-sm text-ink">
            {shortAddress(connection.address)}
          </p>
        ) : null}
        {showAlert && alertMessage !== undefined ? (
          <p role="alert">{alertMessage}</p>
        ) : null}
      </div>
    );
  }

  return (
    <>
      <div className="flex flex-wrap gap-2">
        {connection.isConnected ? (
          <button
            type="button"
            className={actionButtonClass()}
            disabled={busy}
            onClick={() => disconnect.mutate()}
          >
            Disconnect
          </button>
        ) : (
          <button
            type="button"
            className={actionButtonClass()}
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
            className={actionButtonClass()}
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

export function WalletBarAlert({ message }: { message: string | undefined }) {
  if (message === undefined) {
    return null;
  }

  return (
    <p role="alert" className="bg-background px-6 py-2 text-ink">
      <span className="mx-auto block max-w-5xl">{message}</span>
    </p>
  );
}
