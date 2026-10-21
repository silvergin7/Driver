"use client";

import {
  useEffect,
  useId,
  useRef,
  useState,
  useSyncExternalStore,
  type KeyboardEvent as ReactKeyboardEvent,
} from "react";
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
import { withDeadline } from "@/lib/with-deadline";

const revokeDeadlineMs = 2_000;

function wideAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

function narrowAddress(address: string): string {
  return `${address.slice(0, 4)}…${address.slice(-2)}`;
}

function useMinWidth(query: string, serverValue: boolean): boolean {
  return useSyncExternalStore(
    (onStoreChange) => {
      const media = window.matchMedia(query);
      media.addEventListener("change", onStoreChange);
      return () => media.removeEventListener("change", onStoreChange);
    },
    () => window.matchMedia(query).matches,
    () => serverValue,
  );
}

export function useWalletControls() {
  const connection = useConnection();
  const connect = useConnect();
  const connectors = useConnectors();
  const disconnect = useDisconnect();
  const switchChain = useSwitchChain();
  const [accountAlert, setAccountAlert] = useState<string | undefined>();
  const [disconnecting, setDisconnecting] = useState(false);
  const disconnectingRef = useRef(false);
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

  async function disconnectWallet() {
    if (disconnectingRef.current) {
      return;
    }
    setAccountAlert(undefined);
    connect.reset();
    switchChain.reset();
    const active = connection.connector;
    disconnectingRef.current = true;
    setDisconnecting(true);
    try {
      try {
        if (active !== undefined) {
          const provider = await active.getProvider();
          if (isRequestProvider(provider)) {
            await withDeadline(
              provider.request({
                method: "wallet_revokePermissions",
                params: [{ eth_accounts: {} }],
              }),
              revokeDeadlineMs,
            );
          }
        }
      } catch (error: unknown) {
        void error;
      }
      try {
        await disconnect.mutateAsync(active === undefined ? undefined : { connector: active });
      } catch (error: unknown) {
        void error;
      }
    } finally {
      disconnectingRef.current = false;
      setDisconnecting(false);
    }
  }

  return {
    connection,
    connector,
    connect,
    disconnectWallet,
    disconnecting,
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

export type AccountMenuControl = {
  open: boolean;
  onToggle: () => void;
  onClose: () => void;
};

export function ConnectWallet({
  compact = false,
  showAlert = true,
  controls,
  accountMenu,
}: {
  compact?: boolean;
  showAlert?: boolean;
  controls?: WalletControls;
  accountMenu?: AccountMenuControl;
}) {
  if (controls !== undefined) {
    return (
      <WalletMarkup
        controls={controls}
        compact={compact}
        showAlert={showAlert}
        accountMenu={accountMenu}
      />
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

function useAccountMenu(connected: boolean, controlled: AccountMenuControl | undefined) {
  const [localOpen, setLocalOpen] = useState(false);
  const [seenConnected, setSeenConnected] = useState(connected);
  if (connected !== seenConnected) {
    setSeenConnected(connected);
    if (!connected && controlled === undefined) {
      setLocalOpen(false);
    }
  }
  if (controlled !== undefined) {
    return {
      open: controlled.open,
      toggle: controlled.onToggle,
      close: controlled.onClose,
    };
  }
  return {
    open: localOpen,
    toggle: () => setLocalOpen((value) => !value),
    close: () => setLocalOpen(false),
  };
}

function WalletMarkup({
  controls,
  compact,
  showAlert,
  accountMenu,
}: {
  controls: WalletControls;
  compact: boolean;
  showAlert: boolean;
  accountMenu?: AccountMenuControl;
}) {
  const {
    connection,
    connector,
    connect,
    disconnectWallet,
    disconnecting,
    switchChain,
    switchAccount,
    busy,
    onAnvil,
    alertMessage,
    accountAlert,
    connectError,
    switchError,
  } = controls;
  const menu = useAccountMenu(connection.isConnected, accountMenu);

  if (compact) {
    return (
      <div className="flex flex-col items-start gap-2">
        <div className="flex items-center gap-0.5 md:gap-2">
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
                  className="min-h-11 whitespace-nowrap rounded-md bg-brand px-2 py-2 text-sm text-on-brand disabled:border disabled:border-line disabled:bg-disabled-bg disabled:text-ink-muted md:px-3 md:text-base"
                  disabled={busy}
                  onClick={() => switchChain.mutate({ chainId: anvil.id })}
                >
                  Switch to Anvil
                </button>
              ) : null}
              {connection.address !== undefined ? (
                <AccountButton
                  address={connection.address}
                  wideOnly={!onAnvil}
                  open={menu.open}
                  onToggle={menu.toggle}
                  onClose={menu.close}
                  onSwitch={switchAccount}
                  onDisconnect={() => {
                    void disconnectWallet();
                  }}
                  disconnecting={disconnecting}
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
            disabled={busy || disconnecting}
            onClick={() => {
              void disconnectWallet();
            }}
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
  wideOnly,
  open,
  onToggle,
  onClose,
  onSwitch,
  onDisconnect,
  disconnecting,
}: {
  address: string;
  wideOnly: boolean;
  open: boolean;
  onToggle: () => void;
  onClose: () => void;
  onSwitch: () => void;
  onDisconnect: () => void;
  disconnecting: boolean;
}) {
  const menuId = useId();
  const mdUp = useMinWidth("(min-width: 768px)", true);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const switchRef = useRef<HTMLButtonElement>(null);
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  }, [onClose]);
  const visibleAddress = mdUp ? wideAddress(address) : narrowAddress(address);
  const label = wideOnly && !mdUp ? "Account" : `Account, connected as ${visibleAddress}`;

  useEffect(() => {
    if (!open) {
      return;
    }
    switchRef.current?.focus();
    function onKey(event: globalThis.KeyboardEvent) {
      if (event.key !== "Escape") {
        return;
      }
      closeRef.current();
      buttonRef.current?.focus();
    }
    function onPointer(event: PointerEvent) {
      const target = event.target;
      if (!(target instanceof Node)) {
        return;
      }
      if (buttonRef.current?.contains(target)) {
        return;
      }
      if (panelRef.current?.contains(target)) {
        return;
      }
      closeRef.current();
    }
    window.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      window.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
  }, [open]);

  function onMenuKey(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") {
      return;
    }
    event.preventDefault();
    const items = panelRef.current?.querySelectorAll<HTMLButtonElement>(
      '[role="menuitem"]:not(:disabled)',
    );
    if (items === undefined || items.length === 0) {
      return;
    }
    const list = [...items];
    const current = list.indexOf(document.activeElement as HTMLButtonElement);
    const delta = event.key === "ArrowDown" ? 1 : -1;
    const next = list[(current + delta + list.length) % list.length];
    next?.focus();
  }

  return (
    <div className="relative w-fit">
      <button
        ref={buttonRef}
        type="button"
        className={`inline-flex h-11 shrink-0 items-center whitespace-nowrap rounded-md border border-line bg-background font-mono text-sm text-ink hover:bg-surface ${
          wideOnly
            ? "w-11 justify-center px-0 md:w-auto md:justify-start md:gap-1 md:px-2"
            : "gap-0.5 px-0.5 md:gap-1 md:px-2"
        }`}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={menuId}
        aria-label={label}
        title="Account"
        onClick={onToggle}
      >
        <span className={wideOnly ? "hidden" : "md:hidden"}>{narrowAddress(address)}</span>
        <span className="hidden md:inline">{wideAddress(address)}</span>
        <ChevronIcon />
      </button>
      {open ? (
        <div
          ref={panelRef}
          id={menuId}
          role="menu"
          aria-label="Account"
          className="absolute right-0 top-full z-10 mt-2.5 flex w-max flex-col rounded-md border border-line bg-background py-1 shadow-raise"
          onKeyDown={onMenuKey}
        >
          <button
            ref={switchRef}
            type="button"
            role="menuitem"
            className="min-h-11 whitespace-nowrap px-3 text-left text-sm text-ink hover:bg-surface disabled:text-ink-muted"
            disabled={disconnecting}
            onClick={() => {
              onClose();
              onSwitch();
            }}
          >
            Switch account
          </button>
          <button
            type="button"
            role="menuitem"
            className="min-h-11 whitespace-nowrap px-3 text-left text-sm text-ink hover:bg-surface disabled:text-ink-muted"
            disabled={disconnecting}
            onClick={() => {
              onClose();
              onDisconnect();
            }}
          >
            Disconnect
          </button>
        </div>
      ) : null}
    </div>
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
