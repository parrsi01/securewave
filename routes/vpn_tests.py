"""
SecureWave VPN Test Routes - Real VPN Performance Testing

Provides API endpoints for running VPN performance tests
and retrieving test results.

NOTE: These tests measure the ACTUAL OS-level VPN tunnel performance.
The VPN must be connected at the OS level before tests will be meaningful.
"""

import os
import sys
import json
import asyncio
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from database.session import get_db
from models.user import User
from services.jwt_service import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/vpn/tests", tags=["vpn-tests"])

# Path to test suite
TEST_SUITE_DIR = Path(__file__).parent.parent / "securewave-tests"
RESULTS_DIR = Path(
    os.getenv("VPN_TEST_RESULTS_DIR", "/tmp/securewave-tests/results")
)

# Track running tests
_running_tests: Dict[int, bool] = {}  # user_id -> is_running


# =============================================================================
# Request/Response Models
# =============================================================================

class TestRunRequest(BaseModel):
    """Request to run VPN tests"""
    skip_baseline: bool = Field(
        False,
        description="Skip baseline measurements (faster, but no comparison)"
    )
    stability_duration: int = Field(
        30,
        ge=10,
        le=120,
        description="Duration in seconds for stability test"
    )
    quick: bool = Field(
        False,
        description="Run quick test (10s stability, fewer pings)"
    )


class TestScoreBreakdown(BaseModel):
    """Individual test scores"""
    latency: float = 0
    throughput: float = 0
    dns_leak: float = 0
    ipv6_leak: float = 0
    ad_blocking: float = 0
    stability: float = 0


class TestRunResponse(BaseModel):
    """Response from test run"""
    status: str
    message: str
    test_id: Optional[str] = None
    run_id: Optional[str] = None
    results: Optional[Dict[str, Any]] = None


class TestResultSummary(BaseModel):
    """Summary of test results"""
    run_id: Optional[str] = None
    message: Optional[str] = None
    timestamp: str
    vpn_detected: bool
    vpn_interface: Optional[str]
    overall_score: float
    status: str  # PASSED/FAILED
    latency_ms: float
    latency_baseline_ms: Optional[float]
    latency_increase_ms: Optional[float]
    throughput_mbps: float
    throughput_baseline_mbps: Optional[float]
    throughput_retained_percent: Optional[float]
    dns_leak_detected: bool
    ipv6_leak_detected: bool
    ads_blocked_percent: float
    trackers_blocked_percent: float
    tunnel_drops: int
    uptime_percent: float
    test_duration_seconds: float
    scores: TestScoreBreakdown


class TestStatusResponse(BaseModel):
    """Current test status"""
    running: bool
    has_results: bool
    last_run: Optional[str] = None


# =============================================================================
# Helper Functions
# =============================================================================

def get_latest_results() -> Optional[Dict[str, Any]]:
    """Load latest test results from file"""
    latest_path = RESULTS_DIR / "latest.json"

    if not latest_path.exists():
        return None

    try:
        with open(latest_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load test results: {e}")
        return None


def results_to_summary(results: Dict[str, Any]) -> TestResultSummary:
    """Convert raw results to summary format"""
    scoring = results.get('scoring', {})
    individual_scores = scoring.get('individual_scores', {})

    baseline = results.get('baseline', {})
    latency = results.get('latency', {})
    throughput = results.get('throughput', {})
    latency_cmp = results.get('latency_comparison', {})
    throughput_cmp = results.get('throughput_comparison', {})
    dns_leak = results.get('dns_leak', {})
    ipv6_leak = results.get('ipv6_leak', {})
    ad_blocking = results.get('ad_blocking', {})
    stability = results.get('stability', {})

    return TestResultSummary(
        run_id=results.get('run_id'),
        message=results.get('message'),
        timestamp=results.get('timestamp', datetime.now().isoformat()),
        vpn_detected=results.get('vpn_detected', False),
        vpn_interface=results.get('vpn_interface'),
        overall_score=scoring.get('overall_score', 0),
        status=scoring.get('status', 'UNKNOWN'),
        latency_ms=latency.get('avg_latency_ms', 0),
        latency_baseline_ms=baseline.get('latency_ms'),
        latency_increase_ms=latency_cmp.get('difference_ms'),
        throughput_mbps=throughput.get('avg_download_mbps', 0),
        throughput_baseline_mbps=baseline.get('throughput_mbps'),
        throughput_retained_percent=throughput_cmp.get('retained_percent'),
        dns_leak_detected=dns_leak.get('leak_detected', False),
        ipv6_leak_detected=ipv6_leak.get('leak_detected', False),
        ads_blocked_percent=ad_blocking.get('ads_blocked_percent', 0),
        trackers_blocked_percent=ad_blocking.get('trackers_blocked_percent', 0),
        tunnel_drops=stability.get('tunnel_drops', 0),
        uptime_percent=stability.get('uptime_percent', 0),
        test_duration_seconds=results.get('test_duration_seconds', 0),
        scores=TestScoreBreakdown(**individual_scores)
    )


def build_failure_results(run_id: str, message: str) -> Dict[str, Any]:
    """Build a safe failure payload that won't break the UI."""
    return {
        "run_id": run_id,
        "message": message,
        "timestamp": datetime.now().isoformat(),
        "vpn_detected": False,
        "vpn_interface": None,
        "latency": {"avg_latency_ms": 0},
        "throughput": {"avg_download_mbps": 0},
        "dns_leak": {"leak_detected": False},
        "ipv6_leak": {"leak_detected": False},
        "ad_blocking": {"ads_blocked_percent": 0, "trackers_blocked_percent": 0},
        "stability": {"tunnel_drops": 0, "uptime_percent": 0},
        "scoring": {"overall_score": 0, "status": "FAILED", "individual_scores": {}},
        "test_duration_seconds": 0,
    }


async def run_tests_async(
    user_id: int,
    skip_baseline: bool = False,
    stability_duration: int = 30,
    timeout_seconds: int = 90,
    run_id: Optional[str] = None
) -> Dict[str, Any]:
    """Run tests asynchronously"""
    global _running_tests
    run_id = run_id or f"run_{user_id}_{uuid4().hex[:8]}"

    _running_tests[user_id] = True

    try:
        logger.info(json.dumps({
            "event": "vpn_test_start",
            "run_id": run_id,
            "user_id": user_id,
            "skip_baseline": skip_baseline,
            "stability_duration": stability_duration,
            "timeout_seconds": timeout_seconds,
        }))

        loop = asyncio.get_event_loop()

        # Add test suite to path
        sys.path.insert(0, str(TEST_SUITE_DIR))

        # Import test runner
        from runner import run_all_tests, save_results

        # Run tests in thread pool to avoid blocking
        results = await asyncio.wait_for(
            loop.run_in_executor(
                None,
                lambda: run_all_tests(
                    skip_baseline=skip_baseline,
                    stability_duration=stability_duration,
                    verbose=False
                )
            ),
            timeout=timeout_seconds
        )

        # Save results
        results["run_id"] = run_id
        await loop.run_in_executor(
            None,
            lambda: save_results(results, str(RESULTS_DIR))
        )

        logger.info(json.dumps({
            "event": "vpn_test_complete",
            "run_id": run_id,
            "user_id": user_id,
            "status": results.get("scoring", {}).get("status"),
        }))

        return results

    except asyncio.TimeoutError:
        message = "VPN test timed out. Please try again or use Quick Test."
        logger.error(json.dumps({
            "event": "vpn_test_timeout",
            "run_id": run_id,
            "user_id": user_id,
            "timeout_seconds": timeout_seconds,
        }))
        results = build_failure_results(run_id, message)
        await loop.run_in_executor(
            None,
            lambda: save_results(results, str(RESULTS_DIR))
        )
        return results
    except Exception as e:
        message = "VPN test failed. Please try again."
        logger.error(json.dumps({
            "event": "vpn_test_error",
            "run_id": run_id,
            "user_id": user_id,
            "error": str(e),
        }))
        results = build_failure_results(run_id, message)
        await loop.run_in_executor(
            None,
            lambda: save_results(results, str(RESULTS_DIR))
        )
        return results
    finally:
        _running_tests[user_id] = False
        # Clean up path
        if str(TEST_SUITE_DIR) in sys.path:
            sys.path.remove(str(TEST_SUITE_DIR))


# =============================================================================
# API Endpoints
# =============================================================================

@router.get("/status", response_model=TestStatusResponse)
async def get_test_status():
    """
    Get current test status.

    Returns whether a test is running and if results are available.
    Public endpoint - no authentication required.
    """
    # Check if any tests are running
    running = any(_running_tests.values())

    results = get_latest_results()
    has_results = results is not None
    last_run = results.get('timestamp') if results else None

    return TestStatusResponse(
        running=running,
        has_results=has_results,
        last_run=last_run
    )


@router.get("/latest", response_model=TestResultSummary)
async def get_latest_test_results():
    """
    Get the latest test results.

    Returns summarized test results from the most recent test run.
    """
    results = get_latest_results()

    if not results:
        return TestResultSummary(
            run_id=None,
            message="No test results available yet. Run a test to see results.",
            timestamp=datetime.now().isoformat(),
            vpn_detected=False,
            vpn_interface=None,
            overall_score=0,
            status="UNAVAILABLE",
            latency_ms=0,
            latency_baseline_ms=None,
            latency_increase_ms=None,
            throughput_mbps=0,
            throughput_baseline_mbps=None,
            throughput_retained_percent=None,
            dns_leak_detected=False,
            ipv6_leak_detected=False,
            ads_blocked_percent=0,
            trackers_blocked_percent=0,
            tunnel_drops=0,
            uptime_percent=0,
            test_duration_seconds=0,
            scores=TestScoreBreakdown()
        )

    return results_to_summary(results)


@router.get("/latest/full")
async def get_latest_test_results_full():
    """
    Get full test results including all raw data.

    Returns complete test results with all individual measurements.
    """
    results = get_latest_results()

    if not results:
        return build_failure_results(
            run_id=f"no_results_{uuid4().hex[:8]}",
            message="No test results available yet. Run a test to see results."
        )

    return results


@router.post("/run", response_model=TestRunResponse)
async def run_vpn_tests(
    request: TestRunRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user)
):
    """
    Run VPN performance tests.

    Executes the full test suite against the currently active VPN tunnel.
    Tests are run asynchronously and results are saved to disk.

    **Important:** The VPN must be connected at the OS level for meaningful results.

    Tests include:
    - Latency & jitter measurement
    - Throughput (download speed)
    - DNS leak detection
    - IPv6 leak detection
    - Ad/tracker blocking effectiveness
    - Tunnel stability monitoring
    """
    user_id = current_user.id

    # Check if test is already running
    if _running_tests.get(user_id, False):
        return TestRunResponse(
            status="running",
            message="A test is already running. Please wait for it to complete."
        )

    # Determine test parameters
    stability_duration = 10 if request.quick else request.stability_duration
    skip_baseline = request.skip_baseline

    # Check if test suite exists
    if not TEST_SUITE_DIR.exists():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Test suite not found. Please contact support."
        )

    run_id = f"run_{user_id}_{uuid4().hex[:8]}"
    timeout_seconds = int(os.getenv("VPN_TEST_TIMEOUT_SECONDS", "90"))

    # Start test in background
    background_tasks.add_task(
        run_tests_async,
        user_id,
        skip_baseline,
        stability_duration,
        timeout_seconds,
        run_id
    )

    return TestRunResponse(
        status="started",
        message=f"VPN tests started. Duration: ~{stability_duration + 60}s. Check /api/vpn/tests/status for progress.",
        test_id=f"test_{user_id}_{int(datetime.now().timestamp())}",
        run_id=run_id
    )


@router.post("/run/sync", response_model=TestResultSummary)
async def run_vpn_tests_sync(
    request: TestRunRequest,
    current_user: User = Depends(get_current_user)
):
    """
    Run VPN tests synchronously and return results.

    **Warning:** This endpoint may take 60-120 seconds to complete.
    For production use, prefer the async `/run` endpoint.
    """
    user_id = current_user.id

    # Check if test is already running
    if _running_tests.get(user_id, False):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A test is already running. Please wait for it to complete."
        )

    # Check if test suite exists
    if not TEST_SUITE_DIR.exists():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Test suite not found."
        )

    # Determine test parameters
    stability_duration = 10 if request.quick else request.stability_duration
    timeout_seconds = int(os.getenv("VPN_TEST_TIMEOUT_SECONDS", "90"))
    run_id = f"run_{user_id}_{uuid4().hex[:8]}"

    try:
        results = await run_tests_async(
            user_id,
            request.skip_baseline,
            stability_duration,
            timeout_seconds,
            run_id
        )
        return results_to_summary(results)

    except Exception as e:
        logger.error(f"Test run failed: {e}")
        return results_to_summary(build_failure_results(run_id, "VPN test failed. Please try again."))


@router.get("/history")
async def get_test_history(
    limit: int = 10,
    current_user: User = Depends(get_current_user)
):
    """
    Get historical test results.

    Returns a list of past test results sorted by date (newest first).
    """
    if not RESULTS_DIR.exists():
        return {"results": [], "count": 0}

    # Find all result files
    result_files = sorted(
        RESULTS_DIR.glob("results_*.json"),
        key=lambda x: x.stat().st_mtime,
        reverse=True
    )[:limit]

    history = []
    for result_file in result_files:
        try:
            with open(result_file, 'r') as f:
                data = json.load(f)
                summary = results_to_summary(data)
                history.append({
                    "file": result_file.name,
                    "timestamp": summary.timestamp,
                    "overall_score": summary.overall_score,
                    "status": summary.status,
                    "vpn_detected": summary.vpn_detected
                })
        except Exception as e:
            logger.warning(f"Failed to load {result_file}: {e}")

    return {"results": history, "count": len(history)}
