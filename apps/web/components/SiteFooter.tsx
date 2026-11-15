"use client";

/**
 * 网站底部备案条（全站统一，挂在 WritingWorkspace 的 main-area 内，覆盖所有视图）。
 *
 * 合规要求：
 * - ICP 备案号（工信部）已在网站开通后取得，必须展示并链接至工信部备案管理系统。
 * - 公安联网备案（公网安备）是独立的法定义务，编号已下发，必须展示并链接至公安部备案查询页。
 *   若将来编号失效，把 GONGAN_BEIAN_NO 置空即可自动隐藏该区块——绝不显示假的备案号。
 */

// ICP 备案号（工信部），已下发，必须展示。
const ICP_BEIAN_NO = "陕ICP备2026021906号-1";
const ICP_BEIAN_URL = "https://beian.miit.gov.cn";

// 公安联网备案号（公网安备），已下发；留空则不渲染该区块。
const GONGAN_BEIAN_NO = "陕公网安备61019602000894号";
const GONGAN_BEIAN_URL = "https://beian.mps.gov.cn/#/query/webSearch?code=61019602000894";

const SITE_NAME = "墨小小";

export function SiteFooter() {
  const year = new Date().getFullYear();
  return (
    <footer className="site-footer">
      <div className="site-footer-inner">
        <a href={ICP_BEIAN_URL} target="_blank" rel="noopener noreferrer">
          {ICP_BEIAN_NO}
        </a>
        {GONGAN_BEIAN_NO ? (
          <>
            <span className="site-footer-sep">·</span>
            <a href={GONGAN_BEIAN_URL} target="_blank" rel="noopener noreferrer">
              {GONGAN_BEIAN_NO}
            </a>
          </>
        ) : null}
        <span className="site-footer-sep">·</span>
        <a href="/legal/terms" target="_blank" rel="noopener noreferrer">用户协议</a>
        <span className="site-footer-sep">·</span>
        <a href="/legal/privacy" target="_blank" rel="noopener noreferrer">隐私政策</a>
        <span className="site-footer-sep">·</span>
        <span className="site-footer-copy">© {year} {SITE_NAME}</span>
      </div>
    </footer>
  );
}
