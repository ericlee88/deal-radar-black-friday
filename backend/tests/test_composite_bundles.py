import asyncio
import json
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

from app.composite_bundles import (
    COMPOSITE_BUNDLES,
    bundle_price_bounds,
    is_composite_bundle,
    validate_price_update,
)
from app.models import DealOptionNode
from app.providers.price_provider import PriceDataProvider
from scripts import apply_price_updates
from scripts.gemini_search_prices import assemble_bundle_updates


def test_is_composite_bundle_detection():
    assert is_composite_bundle("path_a_adapter_split") is True
    assert is_composite_bundle("diy_metamucil_vital") is True
    assert is_composite_bundle("custom_combo", "B001 + B002") is True
    assert is_composite_bundle("dyson_car_boat", "B0DLXGDHBX / DYSON-CAR-BOAT") is False


def test_validate_price_update_rejects_single_component_bundle_prices():
    # Regression #1: DCA1820 bare adapter ($39.88) must be rejected for DCA1820 + DCB205-2C bundle
    ok, reason = validate_price_update(
        "path_a_adapter_split",
        39.88,
        prev_price=167.88,
        msrp=348.0,
        strike_price=149.0,
    )
    assert ok is False
    assert "composite bundle" in reason

    # Regression #2: Metamucil-only ($38.99) must be rejected for Metamucil + Vital Proteins stack
    ok2, reason2 = validate_price_update(
        "diy_metamucil_vital",
        38.99,
        prev_price=66.94,
        msrp=83.33,
        strike_price=36.0,
    )
    assert ok2 is False
    assert "composite bundle" in reason2

    # Valid combined bundle totals pass
    ok3, _ = validate_price_update(
        "path_a_adapter_split",
        163.87,
        prev_price=167.88,
        msrp=348.0,
        strike_price=149.0,
    )
    assert ok3 is True

    ok4, _ = validate_price_update(
        "diy_metamucil_vital",
        60.74,
        prev_price=66.94,
        msrp=83.33,
        strike_price=36.0,
    )
    assert ok4 is True


def test_validate_price_update_allows_legit_black_friday_drop_but_rejects_garbage():
    # Deep Black Friday drop hitting strike price (e.g. GraviTrax $67.64 -> $26.99) MUST be allowed
    ok, _ = validate_price_update(
        "puzzle_gravitrax",
        26.99,
        prev_price=67.64,
        msrp=69.99,
        strike_price=26.99,
    )
    assert ok is True

    # Garbage scrape: $14.99 accessory mis-matched for a $399.99 Dyson V12
    ok_bad, reason = validate_price_update(
        "dyson_v12_slim",
        14.99,
        prev_price=449.99,
        msrp=729.99,
        strike_price=399.99,
    )
    assert ok_bad is False
    assert "below previous" in reason

    # Garbage spike: $2500 scalper glitch on a $729.99 MSRP item
    ok_spike, _ = validate_price_update(
        "dyson_v12_slim",
        2500.0,
        prev_price=449.99,
        msrp=729.99,
        strike_price=399.99,
    )
    assert ok_spike is False


def test_assemble_bundle_updates_requires_all_components():
    bundle_items = [
        {
            "branch_key": "path_a_adapter_split",
            "current_price": 167.88,
            "msrp": 348.0,
            "strike_price": 149.0,
        },
        {
            "branch_key": "diy_metamucil_vital",
            "current_price": 66.94,
            "msrp": 83.33,
            "strike_price": 36.0,
        },
    ]

    # Only 1 of 2 components verified for path_a_adapter_split -> MUST be omitted
    # Both components verified for diy_metamucil_vital -> MUST be summed accurately
    component_results = {
        "dca1820": {"current_price": 39.88, "msrp": 49.0, "note": "Home Depot"},
        # dcb205_2c intentionally missing!
        "metamucil_180": {"current_price": 28.77, "msrp": 36.33, "note": "Walmart"},
        "vital_proteins_20oz": {"current_price": 31.97, "msrp": 47.0, "note": "Walmart"},
    }

    assembled = assemble_bundle_updates(bundle_items, component_results)
    assert "path_a_adapter_split" not in assembled
    assert "diy_metamucil_vital" in assembled
    assert assembled["diy_metamucil_vital"]["current_price"] == 60.74
    assert assembled["diy_metamucil_vital"]["msrp"] == 83.33
    assert "metamucil_180" in assembled["diy_metamucil_vital"]["components"]
    assert "vital_proteins_20oz" in assembled["diy_metamucil_vital"]["components"]


def test_assemble_bundle_updates_rejects_component_below_floor():
    bundle_items = [
        {
            "branch_key": "path_a_adapter_split",
            "current_price": 167.88,
            "msrp": 348.0,
            "strike_price": 149.0,
        }
    ]
    # Generic $9.99 knockoff adapter should fail dca1820's $20 floor
    component_results = {
        "dca1820": {"current_price": 9.99, "note": "eBay knockoff"},
        "dcb205_2c": {"current_price": 123.99, "note": "Walmart"},
    }
    assembled = assemble_bundle_updates(bundle_items, component_results)
    assert "path_a_adapter_split" not in assembled


def test_price_provider_preserves_composite_bundle_during_poll():
    provider = PriceDataProvider()
    node = DealOptionNode(
        mission_id=1,
        branch_key="diy_metamucil_vital",
        branch_label="Option B",
        title="DIY Stack: Metamucil + Vital Proteins",
        asin_or_sku="B00K6JUG4K / METAMUCIL-180 + VITAL-20OZ",
        amazon_query="Vital+Proteins+Metamucil",
        msrp=83.33,
        avg_90d_price=66.94,
        current_price=60.74,
        clip_coupon_amount=0.0,
        strike_price=36.0,
        all_time_low=55.0,
    )

    with patch.object(provider, "_fetch_amazon_direct", new_callable=AsyncMock) as mock_direct:
        mock_direct.return_value = {
            "current_price": 38.99,
            "avg_90d_price": 38.99,
            "clip_coupon_amount": 0.0,
            "provider": "amazon_direct_live",
        }
        tick = asyncio.run(provider.refresh_node_price(node, simulate_drop=False))
        mock_direct.assert_not_called()
        assert tick["current_price"] == 60.74
        assert tick["provider"] == "composite_bundle_preserved"


def test_apply_price_updates_blocks_bundle_corruption(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    vp_file = tmp_path / "verified_prices.json"
    snap_file = tmp_path / "deals_snapshot.json"
    vp_file.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "updated_at": "",
                "items": {
                    "path_a_adapter_split": {
                        "current_price": 167.88,
                        "msrp": 348.0,
                        "price_history": [167.88],
                        "price_log": [],
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    snap_file.write_text(
        json.dumps(
            {
                "missions": [
                    {
                        "options": [
                            {
                                "branch_key": "path_a_adapter_split",
                                "strike_price": 149.0,
                            }
                        ]
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(apply_price_updates, "VERIFIED_PRICES_FILE", vp_file)
    monkeypatch.setattr(apply_price_updates, "SNAPSHOT_OUTPUT", snap_file)

    count = apply_price_updates._apply_updates(
        {"path_a_adapter_split": {"current_price": 39.88, "note": "Adapter only"}},
        rebuild_snapshot=False,
    )
    assert count == 0
    saved = json.loads(vp_file.read_text(encoding="utf-8"))
    assert saved["items"]["path_a_adapter_split"]["current_price"] == 167.88

    # Valid combined update succeeds
    count2 = apply_price_updates._apply_updates(
        {"path_a_adapter_split": {"current_price": 163.87, "msrp": 348.0, "note": "Combined"}},
        rebuild_snapshot=False,
    )
    assert count2 == 1
    saved2 = json.loads(vp_file.read_text(encoding="utf-8"))
    assert saved2["items"]["path_a_adapter_split"]["current_price"] == 163.87
