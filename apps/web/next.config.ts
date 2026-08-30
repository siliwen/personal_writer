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
  },
  // dev/本地兜底反代：apiBase() 构建期被内联为 "/api"，但 `next dev` 没有
  // nginx 处理 /api/*，会落进 Next.js 404（HTML），登录报
  // "Unexpected token '<', '<!DOCTYPE'"（2026-08-30）。rewrites 把 /api/*
  // 服务端转发到本地 uvicorn :8010。
  // 生产环境：nginx `location /api/` 在请求到达 Next.js 前就已 proxy_pass
  // 到 8010（ec2-deploy.sh），rewrites 不会触发，属无害兜底；
  // 目标地址仅存在于服务端 routes-manifest.json，不进入客户端
  // .next/static/chunks（update-from-tar.sh 自检 grep :8010 不受影响）。
  async rewrites() {
    const apiTarget = process.env.API_PROXY_TARGET || "http://127.0.0.1:8010";
    return [
      { source: "/api/:path*", destination: `${apiTarget}/:path*` },
    ];
  }
};

export default nextConfig;
