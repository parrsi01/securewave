"""
Sentry Error Tracking Service
Integrates with Sentry for error tracking and monitoring
"""

import os
import logging
from typing import Dict, Optional, Any, Callable
from functools import wraps

logger = logging.getLogger(__name__)

# Configuration
SENTRY_DSN = os.getenv("SENTRY_DSN", "")
SENTRY_ENVIRONMENT = os.getenv("SENTRY_ENVIRONMENT", "production")
SENTRY_RELEASE = os.getenv("SENTRY_RELEASE", "1.0.0")
ENABLE_SENTRY = os.getenv("ENABLE_SENTRY", "true").lower() == "true"
SENTRY_TRACES_SAMPLE_RATE = float(os.getenv("SENTRY_TRACES_SAMPLE_RATE", "0.1"))  # 10% of transactions


class SentryService:
    """
    Sentry Error Tracking Service
    Provides error tracking, performance monitoring, and exception handling
    """

    def __init__(self):
        """Initialize Sentry client"""
        self.enabled = ENABLE_SENTRY and SENTRY_DSN
        self.initialized = False

        if self.enabled:
            try:
                import sentry_sdk
                from sentry_sdk.integrations.logging import LoggingIntegration
                from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
                from sentry_sdk.integrations.redis import RedisIntegration

                # Configure logging integration
                logging_integration = LoggingIntegration(
                    level=logging.INFO,        # Capture info and above as breadcrumbs
                    event_level=logging.ERROR  # Send errors and above as events
                )

                # Initialize Sentry
                sentry_sdk.init(
                    dsn=SENTRY_DSN,
                    environment=SENTRY_ENVIRONMENT,
                    release=SENTRY_RELEASE,
                    traces_sample_rate=SENTRY_TRACES_SAMPLE_RATE,
                    integrations=[
                        logging_integration,
                        SqlalchemyIntegration(),
                        RedisIntegration(),
                    ],
                    # Set additional options
                    send_default_pii=False,  # Don't send personally identifiable information
                    attach_stacktrace=True,
                    max_breadcrumbs=50,
                    before_send=self._before_send,
                    before_breadcrumb=self._before_breadcrumb,
                )

                self.initialized = True
                logger.info(f"Sentry initialized successfully (environment: {SENTRY_ENVIRONMENT})")

            except ImportError:
                logger.warning("Sentry SDK not installed. Error tracking disabled.")
                self.enabled = False
            except Exception as e:
                logger.error(f"Failed to initialize Sentry: {e}")
                self.enabled = False

    def _before_send(self, event: Dict, hint: Dict) -> Optional[Dict]:
        """
        Filter events before sending to Sentry

        Args:
            event: Sentry event
            hint: Additional context

        Returns:
            Modified event or None to drop the event
        """
        # Filter out specific exceptions if needed
        if 'exc_info' in hint:
            exc_type, exc_value, tb = hint['exc_info']

            # Don't send certain expected exceptions
            if exc_type.__name__ in ['ValidationError', 'HTTPException']:
                return None

        # Scrub sensitive data
        if 'request' in event:
            request = event['request']

            # Remove sensitive headers
            if 'headers' in request:
                sensitive_headers = ['Authorization', 'Cookie', 'X-API-Key']
                for header in sensitive_headers:
                    if header in request['headers']:
                        request['headers'][header] = '[Filtered]'

            # Remove sensitive query parameters
            if 'query_string' in request:
                sensitive_params = ['password', 'token', 'api_key', 'secret']
                for param in sensitive_params:
                    if param in str(request['query_string']).lower():
                        request['query_string'] = '[Filtered]'

        return event

    def _before_breadcrumb(self, crumb: Dict, hint: Dict) -> Optional[Dict]:
        """
        Filter breadcrumbs before adding to Sentry

        Args:
            crumb: Breadcrumb data
            hint: Additional context

        Returns:
            Modified breadcrumb or None to drop it
        """
        # Filter sensitive data from breadcrumbs
        if crumb.get('category') == 'query':
            # Filter SQL queries with sensitive data
            if 'message' in crumb:
                message = str(crumb['message']).lower()
                if any(word in message for word in ['password', 'token', 'secret']):
                    crumb['message'] = '[Filtered SQL Query]'

        return crumb

    # ===========================
    # ERROR TRACKING
    # ===========================

    def capture_exception(
        self,
        exception: Exception,
        level: str = "error",
        tags: Optional[Dict[str, str]] = None,
        extras: Optional[Dict[str, Any]] = None,
        user: Optional[Dict[str, str]] = None
    ) -> Optional[str]:
        """
        Capture an exception

        Args:
            exception: Exception instance
            level: Error level (debug, info, warning, error, fatal)
            tags: Custom tags
            extras: Extra context data
            user: User context

        Returns:
            Event ID or None
        """
        if not self.enabled or not self.initialized:
            return None

        try:
            import sentry_sdk

            # Set scope
            with sentry_sdk.push_scope() as scope:
                scope.level = level

                # Add tags
                if tags:
                    for key, value in tags.items():
                        scope.set_tag(key, value)

                # Add extras
                if extras:
                    for key, value in extras.items():
                        scope.set_extra(key, value)

                # Set user context
                if user:
                    scope.set_user(user)

                # Capture exception
                event_id = sentry_sdk.capture_exception(exception)
                return event_id

        except Exception as e:
            logger.error(f"Failed to capture exception in Sentry: {e}")
            return None

    def capture_message(
        self,
        message: str,
        level: str = "info",
        tags: Optional[Dict[str, str]] = None,
        extras: Optional[Dict[str, Any]] = None
    ) -> Optional[str]:
        """
        Capture a message

        Args:
            message: Message to capture
            level: Message level
            tags: Custom tags
            extras: Extra context data

        Returns:
            Event ID or None
        """
        if not self.enabled or not self.initialized:
            return None

        try:
            import sentry_sdk

            with sentry_sdk.push_scope() as scope:
                scope.level = level

                if tags:
                    for key, value in tags.items():
                        scope.set_tag(key, value)

                if extras:
                    for key, value in extras.items():
                        scope.set_extra(key, value)

                event_id = sentry_sdk.capture_message(message)
                return event_id

        except Exception as e:
            logger.error(f"Failed to capture message in Sentry: {e}")
            return None

    # ===========================
    # CONTEXT & BREADCRUMBS
    # ===========================

    def add_breadcrumb(
        self,
        message: str,
        category: str = "default",
        level: str = "info",
        data: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Add a breadcrumb for context

        Args:
            message: Breadcrumb message
            category: Category (navigation, http, auth, etc.)
            level: Level (debug, info, warning, error, fatal)
            data: Additional data
        """
        if not self.enabled or not self.initialized:
            return

        try:
            import sentry_sdk

            sentry_sdk.add_breadcrumb(
                category=category,
                message=message,
                level=level,
                data=data or {}
            )

        except Exception as e:
            logger.error(f"Failed to add breadcrumb: {e}")

    def set_user(self, user_id: str, email: Optional[str] = None, username: Optional[str] = None) -> None:
        """
        Set user context

        Args:
            user_id: User ID
            email: User email
            username: Username
        """
        if not self.enabled or not self.initialized:
            return

        try:
            import sentry_sdk

            sentry_sdk.set_user({
                "id": user_id,
                "email": email,
                "username": username
            })

        except Exception as e:
            logger.error(f"Failed to set user context: {e}")

    def set_tag(self, key: str, value: str) -> None:
        """
        Set a global tag

        Args:
            key: Tag key
            value: Tag value
        """
        if not self.enabled or not self.initialized:
            return

        try:
            import sentry_sdk
            sentry_sdk.set_tag(key, value)

        except Exception as e:
            logger.error(f"Failed to set tag: {e}")

    def set_context(self, key: str, value: Dict[str, Any]) -> None:
        """
        Set additional context

        Args:
            key: Context key
            value: Context data
        """
        if not self.enabled or not self.initialized:
            return

        try:
            import sentry_sdk
            sentry_sdk.set_context(key, value)

        except Exception as e:
            logger.error(f"Failed to set context: {e}")

    # ===========================
    # PERFORMANCE MONITORING
    # ===========================

    def start_transaction(self, name: str, op: str = "function") -> Any:
        """
        Start a performance transaction

        Args:
            name: Transaction name
            op: Operation type

        Returns:
            Transaction object or None
        """
        if not self.enabled or not self.initialized:
            return None

        try:
            import sentry_sdk
            transaction = sentry_sdk.start_transaction(name=name, op=op)
            return transaction

        except Exception as e:
            logger.error(f"Failed to start transaction: {e}")
            return None

    def measure_performance(self, operation_name: str, operation_type: str = "function"):
        """
        Decorator to measure function performance

        Args:
            operation_name: Name of the operation
            operation_type: Type of operation (function, http, db, etc.)

        Usage:
            @sentry.measure_performance("process_payment", "payment")
            def process_payment(amount):
                # ... implementation
        """
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            def wrapper(*args, **kwargs):
                if not self.enabled or not self.initialized:
                    return func(*args, **kwargs)

                import sentry_sdk

                with sentry_sdk.start_transaction(op=operation_type, name=operation_name):
                    try:
                        result = func(*args, **kwargs)
                        return result
                    except Exception as e:
                        sentry_sdk.capture_exception(e)
                        raise

            return wrapper
        return decorator

    # ===========================
    # FASTAPI INTEGRATION
    # ===========================

    def get_fastapi_middleware(self):
        """
        Get FastAPI middleware for Sentry

        Returns:
            Sentry FastAPI middleware
        """
        if not self.enabled or not self.initialized:
            return None

        try:
            from sentry_sdk.integrations.asgi import SentryAsgiMiddleware
            return SentryAsgiMiddleware

        except ImportError:
            logger.warning("Sentry ASGI integration not available")
            return None

    # ===========================
    # BUSINESS-SPECIFIC TRACKING
    # ===========================

    def track_login_failure(self, email: str, reason: str, ip_address: str) -> None:
        """Track failed login attempt"""
        self.add_breadcrumb(
            message=f"Login failed: {reason}",
            category="auth",
            level="warning",
            data={
                "email": email,
                "reason": reason,
                "ip_address": ip_address
            }
        )

    def track_payment_failure(self, user_id: int, amount: float, error: str) -> None:
        """Track failed payment"""
        self.capture_message(
            message=f"Payment failed for user {user_id}",
            level="error",
            tags={
                "payment_status": "failed",
                "user_id": str(user_id)
            },
            extras={
                "amount": amount,
                "error": error
            }
        )

    def track_vpn_connection_failure(self, user_id: int, server_id: int, error: str) -> None:
        """Track failed VPN connection"""
        self.capture_message(
            message=f"VPN connection failed for user {user_id}",
            level="warning",
            tags={
                "connection_status": "failed",
                "user_id": str(user_id),
                "server_id": str(server_id)
            },
            extras={
                "error": error
            }
        )

    def track_abuse_detected(self, user_id: int, incident_type: str, severity: str) -> None:
        """Track abuse detection"""
        self.capture_message(
            message=f"Abuse detected: {incident_type}",
            level="error" if severity == "critical" else "warning",
            tags={
                "abuse_type": incident_type,
                "severity": severity,
                "user_id": str(user_id)
            }
        )


# Singleton instance
_sentry_service: Optional[SentryService] = None


def get_sentry_service() -> SentryService:
    """Get Sentry service instance"""
    global _sentry_service
    if _sentry_service is None:
        _sentry_service = SentryService()
    return _sentry_service


# Exception handler decorator
def capture_exceptions(
    reraise: bool = True,
    level: str = "error",
    tags: Optional[Dict[str, str]] = None
):
    """
    Decorator to automatically capture exceptions

    Args:
        reraise: Whether to reraise the exception
        level: Error level
        tags: Custom tags

    Usage:
        @capture_exceptions(reraise=True)
        def my_function():
            # ... implementation
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                sentry = get_sentry_service()
                sentry.capture_exception(
                    exception=e,
                    level=level,
                    tags=tags or {},
                    extras={
                        "function": func.__name__,
                        "module": func.__module__
                    }
                )
                if reraise:
                    raise
                return None

        return wrapper
    return decorator
