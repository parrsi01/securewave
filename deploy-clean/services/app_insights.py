"""
Application Insights Integration Service
Integrates with Azure Application Insights for application telemetry and monitoring
"""

import os
import logging
import time
from typing import Dict, Optional, Any
from datetime import datetime
from functools import wraps

logger = logging.getLogger(__name__)

# Configuration
APP_INSIGHTS_CONNECTION_STRING = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING", "")
APP_INSIGHTS_INSTRUMENTATION_KEY = os.getenv("APPINSIGHTS_INSTRUMENTATIONKEY", "")
ENABLE_APP_INSIGHTS = os.getenv("ENABLE_APP_INSIGHTS", "true").lower() == "true"


class ApplicationInsightsService:
    """
    Application Insights Service
    Provides telemetry tracking for Azure Monitor
    """

    def __init__(self):
        """Initialize Application Insights client"""
        self.enabled = ENABLE_APP_INSIGHTS and (APP_INSIGHTS_CONNECTION_STRING or APP_INSIGHTS_INSTRUMENTATION_KEY)
        self.telemetry_client = None

        if self.enabled:
            try:
                from opencensus.ext.azure.log_exporter import AzureLogHandler
                from opencensus.ext.azure import metrics_exporter
                from applicationinsights import TelemetryClient

                # Initialize telemetry client
                if APP_INSIGHTS_CONNECTION_STRING:
                    self.telemetry_client = TelemetryClient(APP_INSIGHTS_CONNECTION_STRING)
                else:
                    self.telemetry_client = TelemetryClient(APP_INSIGHTS_INSTRUMENTATION_KEY)

                logger.info("Application Insights initialized successfully")
            except ImportError:
                logger.warning("Application Insights libraries not installed. Telemetry disabled.")
                self.enabled = False
            except Exception as e:
                logger.error(f"Failed to initialize Application Insights: {e}")
                self.enabled = False

    # ===========================
    # EVENT TRACKING
    # ===========================

    def track_event(
        self,
        name: str,
        properties: Optional[Dict[str, Any]] = None,
        measurements: Optional[Dict[str, float]] = None
    ) -> None:
        """
        Track a custom event

        Args:
            name: Event name
            properties: Custom properties (string key-value pairs)
            measurements: Custom measurements (numeric key-value pairs)
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.track_event(
                name,
                properties=properties or {},
                measurements=measurements or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track event '{name}': {e}")

    def track_request(
        self,
        name: str,
        url: str,
        success: bool,
        duration_ms: int,
        response_code: int = 200,
        properties: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Track an HTTP request

        Args:
            name: Request name (e.g., "GET /api/users")
            url: Full request URL
            success: Whether request was successful
            duration_ms: Request duration in milliseconds
            response_code: HTTP response code
            properties: Additional properties
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.track_request(
                name,
                url,
                success,
                start_time=None,  # Will use current time
                duration=duration_ms,
                response_code=response_code,
                http_method=properties.get("method", "GET") if properties else "GET",
                properties=properties or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track request '{name}': {e}")

    def track_dependency(
        self,
        name: str,
        dependency_type: str,
        success: bool,
        duration_ms: int,
        properties: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Track a dependency call (database, external API, etc.)

        Args:
            name: Dependency name (e.g., "PostgreSQL query")
            dependency_type: Type (e.g., "SQL", "HTTP", "Azure Service")
            success: Whether call was successful
            duration_ms: Call duration in milliseconds
            properties: Additional properties
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.track_dependency(
                name,
                dependency_type,
                name,  # data (command/query)
                success,
                duration=duration_ms,
                properties=properties or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track dependency '{name}': {e}")

    # ===========================
    # EXCEPTION TRACKING
    # ===========================

    def track_exception(
        self,
        exception: Exception,
        properties: Optional[Dict[str, Any]] = None,
        measurements: Optional[Dict[str, float]] = None
    ) -> None:
        """
        Track an exception

        Args:
            exception: Exception instance
            properties: Custom properties
            measurements: Custom measurements
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            import sys
            self.telemetry_client.track_exception(
                type(exception),
                exception,
                sys.exc_info()[2],
                properties=properties or {},
                measurements=measurements or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track exception: {e}")

    # ===========================
    # METRICS TRACKING
    # ===========================

    def track_metric(
        self,
        name: str,
        value: float,
        properties: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Track a custom metric

        Args:
            name: Metric name
            value: Metric value
            properties: Custom properties
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.track_metric(
                name,
                value,
                properties=properties or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track metric '{name}': {e}")

    # ===========================
    # TRACE LOGGING
    # ===========================

    def track_trace(
        self,
        message: str,
        severity: str = "INFO",
        properties: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Track a trace message

        Args:
            message: Log message
            severity: Severity level (VERBOSE, INFO, WARNING, ERROR, CRITICAL)
            properties: Custom properties
        """
        if not self.enabled or not self.telemetry_client:
            return

        try:
            from applicationinsights.channel import TelemetryChannel

            # Map severity to Application Insights severity
            severity_map = {
                "VERBOSE": 0,
                "INFO": 1,
                "WARNING": 2,
                "ERROR": 3,
                "CRITICAL": 4
            }

            self.telemetry_client.track_trace(
                message,
                severity=severity_map.get(severity.upper(), 1),
                properties=properties or {}
            )
            self.telemetry_client.flush()
        except Exception as e:
            logger.error(f"Failed to track trace: {e}")

    # ===========================
    # PERFORMANCE MONITORING
    # ===========================

    def measure_performance(self, operation_name: str):
        """
        Decorator to measure function performance

        Usage:
            @app_insights.measure_performance("database_query")
            def query_users():
                # ... implementation
        """
        def decorator(func):
            @wraps(func)
            def wrapper(*args, **kwargs):
                if not self.enabled:
                    return func(*args, **kwargs)

                start_time = time.time()
                success = True
                error = None

                try:
                    result = func(*args, **kwargs)
                    return result
                except Exception as e:
                    success = False
                    error = e
                    raise
                finally:
                    duration_ms = int((time.time() - start_time) * 1000)

                    # Track as dependency
                    self.track_dependency(
                        name=f"{func.__module__}.{func.__name__}",
                        dependency_type="Function",
                        success=success,
                        duration_ms=duration_ms,
                        properties={
                            "operation": operation_name,
                            "function": func.__name__,
                            "error": str(error) if error else None
                        }
                    )

            return wrapper
        return decorator

    # ===========================
    # BUSINESS METRICS
    # ===========================

    def track_user_login(self, user_id: int, success: bool, method: str = "password") -> None:
        """Track user login event"""
        self.track_event(
            "UserLogin",
            properties={
                "user_id": str(user_id),
                "success": success,
                "method": method
            },
            measurements={
                "login_count": 1
            }
        )

    def track_user_registration(self, user_id: int) -> None:
        """Track user registration event"""
        self.track_event(
            "UserRegistration",
            properties={"user_id": str(user_id)},
            measurements={"registration_count": 1}
        )

    def track_subscription_created(self, user_id: int, plan: str, amount: float) -> None:
        """Track subscription creation"""
        self.track_event(
            "SubscriptionCreated",
            properties={
                "user_id": str(user_id),
                "plan": plan
            },
            measurements={
                "amount": amount,
                "subscription_count": 1
            }
        )

    def track_vpn_connection(self, user_id: int, server_id: int, success: bool) -> None:
        """Track VPN connection attempt"""
        self.track_event(
            "VPNConnection",
            properties={
                "user_id": str(user_id),
                "server_id": str(server_id),
                "success": success
            },
            measurements={
                "connection_count": 1
            }
        )

    def track_payment(self, user_id: int, amount: float, currency: str, provider: str, success: bool) -> None:
        """Track payment transaction"""
        self.track_event(
            "Payment",
            properties={
                "user_id": str(user_id),
                "currency": currency,
                "provider": provider,
                "success": success
            },
            measurements={
                "amount": amount,
                "payment_count": 1
            }
        )

    # ===========================
    # CUSTOM DIMENSIONS
    # ===========================

    def set_cloud_role(self, role_name: str, role_instance: str) -> None:
        """Set cloud role for telemetry"""
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.context.cloud.role = role_name
            self.telemetry_client.context.cloud.role_instance = role_instance
        except Exception as e:
            logger.error(f"Failed to set cloud role: {e}")

    def set_user_context(self, user_id: str, account_id: Optional[str] = None) -> None:
        """Set user context for telemetry"""
        if not self.enabled or not self.telemetry_client:
            return

        try:
            self.telemetry_client.context.user.id = user_id
            if account_id:
                self.telemetry_client.context.user.account_id = account_id
        except Exception as e:
            logger.error(f"Failed to set user context: {e}")


class FastAPIMiddleware:
    """
    FastAPI middleware for automatic request tracking
    """

    def __init__(self, app_insights: ApplicationInsightsService):
        self.app_insights = app_insights

    async def __call__(self, request, call_next):
        """Track FastAPI requests automatically"""
        import time
        import uuid

        # Generate request ID
        request_id = str(uuid.uuid4())
        start_time = time.time()

        # Add request ID to request state
        request.state.request_id = request_id

        try:
            # Process request
            response = await call_next(request)
            success = response.status_code < 400

            # Calculate duration
            duration_ms = int((time.time() - start_time) * 1000)

            # Track request
            self.app_insights.track_request(
                name=f"{request.method} {request.url.path}",
                url=str(request.url),
                success=success,
                duration_ms=duration_ms,
                response_code=response.status_code,
                properties={
                    "method": request.method,
                    "request_id": request_id,
                    "user_agent": request.headers.get("user-agent", ""),
                    "client_ip": request.client.host if request.client else ""
                }
            )

            # Add request ID to response headers
            response.headers["X-Request-ID"] = request_id

            return response

        except Exception as e:
            # Track exception
            duration_ms = int((time.time() - start_time) * 1000)

            self.app_insights.track_exception(
                exception=e,
                properties={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path
                }
            )

            # Track failed request
            self.app_insights.track_request(
                name=f"{request.method} {request.url.path}",
                url=str(request.url),
                success=False,
                duration_ms=duration_ms,
                response_code=500,
                properties={
                    "method": request.method,
                    "request_id": request_id,
                    "error": str(e)
                }
            )

            raise


# Singleton instance
_app_insights_service: Optional[ApplicationInsightsService] = None


def get_app_insights_service() -> ApplicationInsightsService:
    """Get Application Insights service instance"""
    global _app_insights_service
    if _app_insights_service is None:
        _app_insights_service = ApplicationInsightsService()
    return _app_insights_service
