"use client";

import { useState } from "react";
import {
  useConnection,
  useConnect,
  useConnectors,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { anvil } from "@/config/contracts";
import { actionButtonClass } from "@/lib/control-class";
import { switchAccountError } from "@/lib/switch-account";
import { walletAlertText } from "@/lib/wallet-alert";
import { walletErrorMessage, walletFailedMessage } from "@/lib/wallet-errors";

function wideAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

function narrowAddress(address: string): string {
  return `${address.slice(0, 4)}…${address.slice(-2)}`;
}

export function useWalletControls() {
  const connection = useConnection();
  const connect = useConnect();
  const connectors = useConnectors();
  const disconnect = useDisconnect();
  const switchChain = useSwitchChain();
  const [accountAlert, setAccountAlert] = useState<string | undefined>();
  const address = connection.address;
  const [alertAddress, setAlertAddress] = useState(address);
  if (address !== alertAddress) {
    setAlertAddress(address);
    setAccountAlert(undefined);
  }
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

  async function switchAccount() {
    setAccountAlert(undefined);
    const active = connection.connector;
    try {
      if (active === undefined) {
        setAccountAlert(walletFailedMessage);
        return;
      }
      const provider = await active.getProvider();
      if (!isRequestProvider(provider)) {
        setAccountAlert(walletFailedMessage);
        return;
      }
      await provider.request({
        method: "wallet_requestPermissions",
        params: [{ eth_accounts: {} }],
      });
    } catch (error) {
      setAccountAlert(switchAccountError(error));
    }
  }

  return {
    connection,
    connector,
    connect,
    disconnect,
    switchChain,
    switchAccount,
    busy,
    onAnvil,
    alertMessage,
    accountAlert: connection.isConnected ? accountAlert : undefined,
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
    switchAccount,
    busy,
    onAnvil,
    alertMessage,
    accountAlert,
    connectError,
    switchError,
  } = controls;

  if (compact) {
    return (
      <div className="flex flex-col items-start gap-2">
        <div className="flex items-center gap-1 md:gap-2">
          {!connection.isConnected ? (
            <button
              type="button"
              className={`${actionButtonClass()} whitespace-nowrap`}
              disabled={busy || connector === undefined}
              onClick={() => {
                if (connector) {
                  connect.mutate({ connector });
                }
              }}
            >
              Connect wallet
            </button>
          ) : (
            <>
              {!onAnvil ? (
                <button
                  type="button"
                  className={`${actionButtonClass()} whitespace-nowrap`}
                  disabled={busy}
                  onClick={() => switchChain.mutate({ chainId: anvil.id })}
                >
                  Switch to Anvil
                </button>
              ) : null}
              {connection.address !== undefined ? (
                <AccountButton
                  address={connection.address}
                  onSwitch={switchAccount}
                  wideOnly={!onAnvil}
                />
              ) : null}
            </>
          )}
        </div>
        {showAlert && (accountAlert ?? alertMessage) !== undefined ? (
          <p role="alert">{accountAlert ?? alertMessage}</p>
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

function AccountButton({
  address,
  onSwitch,
  wideOnly,
}: {
  address: string;
  onSwitch: () => void;
  wideOnly: boolean;
}) {
  return (
    <button
      type="button"
      className={`${wideOnly ? "hidden md:inline-flex" : "inline-flex"} h-11 shrink-0 items-center gap-0.5 whitespace-nowrap rounded-md border border-line bg-background px-0.5 font-mono text-sm text-ink hover:bg-surface md:gap-1 md:px-2`}
      aria-label={`Switch account, connected as ${wideAddress(address)}`}
      title="Switch account"
      onClick={onSwitch}
    >
      <span className="md:hidden">{narrowAddress(address)}</span>
      <span className="hidden md:inline">{wideAddress(address)}</span>
      <ChevronIcon />
    </button>
  );
}

function ChevronIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" className="h-3 w-3 md:h-4 md:w-4">
      <path
        d="M6 9l6 6 6-6"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function isRequestProvider(provider: unknown): provider is {
  request: (args: { method: string; params?: readonly unknown[] }) => Promise<unknown>;
} {
  return (
    typeof provider === "object" &&
    provider !== null &&
    "request" in provider &&
    typeof provider.request === "function"
  );
}

export function WalletBarAlert({ message }: { message: string | undefined }) {
  if (message === undefined) {
    return null;
  }

  return (
    <p role="alert" className="bg-background px-4 py-2 text-ink md:px-6">
      <span className="mx-auto block max-w-5xl">{message}</span>
    </p>
  );
}
