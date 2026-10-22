import type { NextConfig } from "next";
import { assertVercelChain } from "./src/config/vercel-chain";

assertVercelChain(process.env.VERCEL, process.env.NEXT_PUBLIC_CHAIN);

const nextConfig: NextConfig = {
  devIndicators: false,
  reactCompiler: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
