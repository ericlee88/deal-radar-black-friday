from fastapi.testclient import TestClient
from app.main import app


def test_health_and_seeded_missions():
    with TestClient(app) as client:
        health = client.get("/api/health")
        assert health.status_code == 200
        h_data = health.json()
        assert h_data["status"] == "ok"
        assert h_data["missions_count"] >= 7

        missions_resp = client.get("/api/missions")
        assert missions_resp.status_code == 200
        missions = missions_resp.json()
        assert len(missions) >= 7
        node_types = {m["node_type"] for m in missions}
        assert "EXACT_SKU" in node_types
        assert "XOR_FORK" in node_types
        assert "CATEGORY_FUNNEL" in node_types
        assert "CONSUMABLE_STACK" in node_types


def test_llm_intent_translation_and_stack_solver():
    with TestClient(app) as client:
        # Test translating a fork intent into an XOR_FORK mission
        resp = client.post(
            "/api/missions/from-intent",
            json={
                "raw_intent": "Anker Prime 250W GaN Charger or Ugreen Nexode 300W desktop charger",
                "budget_hint": 119.0,
            },
        )
        assert resp.status_code == 200
        new_mission = resp.json()
        assert new_mission["node_type"] == "XOR_FORK"
        assert len(new_mission["options"]) == 2

        # Verify Combinatoric Stack Summary (S&S 15% + P&G $100->$25 + 3-for-2)
        stack_resp = client.get("/api/stack-summary")
        assert stack_resp.status_code == 200
        stack = stack_resp.json()
        assert stack["sns_active_count"] >= 5
        assert stack["sns_unlocked_15pct"] is True
        assert stack["pg_credit_unlocked"] == 25.0
        assert stack["b2g1_selected_count"] == 3
        assert stack["b2g1_free_item_deduction"] > 0

        # Clean up created mission
        del_resp = client.delete(f"/api/missions/{new_mission['id']}")
        assert del_resp.status_code == 200


def test_price_patch_and_webhook_alert_trigger():
    with TestClient(app) as client:
        missions = client.get("/api/missions").json()
        # Pick Work Sharp WSSA0004772 option (currently $58.99 vs $56.00 strike)
        ws_mission = next(m for m in missions if "work-sharp" in m["slug"])
        opt_id = ws_mission["options"][0]["id"]

        # Patch price below strike ($52.00 <= $56.00) -> should trigger a strike alert
        patch_resp = client.patch(
            f"/api/options/{opt_id}",
            json={"current_price": 52.00},
        )
        assert patch_resp.status_code == 200
        updated = patch_resp.json()
        assert updated["is_below_strike"] is True

        alerts = client.get("/api/alerts").json()
        assert len(alerts) >= 1
        assert alerts[0]["option_id"] == opt_id
