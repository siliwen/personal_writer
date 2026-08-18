from __future__ import annotations

import uuid

from fastapi.testclient import TestClient

from app import models
from app.database import SessionLocal
from app.main import app


def _login(client: TestClient) -> str:
    """注册一个新用户并返回 user_id（会话 cookie 由 TestClient 自动保留）。"""
    resp = client.post(
        "/v1/auth/register",
        json={
            "username": f"summary_user_{uuid.uuid4().hex[:8]}",
            "password": "writer123",
            "confirm_password": "writer123",
            "agreed_terms": True,
        },
    )
    assert resp.status_code == 200, resp.text
    me = client.get("/v1/me").json()
    return me["user_id"]


def test_dashboard_summary_requires_auth() -> None:
    client = TestClient(app)
    resp = client.get("/v1/dashboard/summary")
    assert resp.status_code == 401


def test_dashboard_summary_zero_state_schema() -> None:
    client = TestClient(app)
    user_id = _login(client)

    resp = client.get("/v1/dashboard/summary")
    assert resp.status_code == 200, resp.text
    body = resp.json()

    # 合并接口应返回计数、额度与最近列表
    assert body["materials_count"] == 0
    assert body["styles_count"] == 0
    assert body["saved_count"] == 0
    assert isinstance(body["recent_styles"], list) and body["recent_styles"] == []
    assert isinstance(body["recent_documents"], list) and body["recent_documents"] == []
    # 额度结构应完整，可用于前端顶栏与写作预校验
    quota = body["quota"]
    assert quota is not None
    assert "points_balance" in quota
    assert "tier" in quota
    assert user_id  # 确保登录链路可用


def test_dashboard_summary_reflects_seeded_data() -> None:
    """summary 接口的计数应真实反映数据库中的参考作品/风格/已保存文章。"""
    client = TestClient(app)
    user_id = _login(client)

    style_id = f"sp_{uuid.uuid4().hex[:12]}"
    doc_id = f"doc_{uuid.uuid4().hex[:12]}"
    with SessionLocal() as db:
        db.add(
            models.StyleProfile(
                id=style_id,
                user_id=user_id,
                name="测试风格",
                profile={"voice": {"tone": ["克制"]}},
                is_default=False,
            )
        )
        db.add(
            models.Material(
                id=f"mat_{uuid.uuid4().hex[:12]}",
                user_id=user_id,
                title="参考文章",
                genre="散文",
                source_type="text",
                content="这是一篇用于风格抽取的参考作品。",
                char_count=15,
                paragraph_count=1,
            )
        )
        db.add(
            models.Document(
                id=doc_id,
                user_id=user_id,
                style_profile_id=style_id,
                title="已保存文章",
                genre="散文",
                content="正文内容。",
                is_saved=True,
                saved_at=__import__("datetime").datetime.now(__import__("datetime").timezone.utc),
            )
        )
        db.commit()

    resp = client.get("/v1/dashboard/summary")
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["materials_count"] == 1
    assert body["styles_count"] == 1
    assert body["saved_count"] == 1
    assert len(body["recent_styles"]) == 1
    assert body["recent_styles"][0]["id"] == style_id
    assert len(body["recent_documents"]) == 1
    assert body["recent_documents"][0]["id"] == doc_id
