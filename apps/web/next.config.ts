import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  devIndicators: false,
  // NEXT_PUBLIC_* 变量必须在构建时内联进客户端 bundle，运行时设置无效。
  // 显式兜底为 /api：即使构建环境未传递该变量，也不会 fallback 到 :8010 直连
  // 导致登录失败（8-14、8-24 两度因环境变量丢失而复发）。
  env: {
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL || "/api"
  }
};

export default nextConfig;
