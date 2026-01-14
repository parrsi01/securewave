"""
Performance Monitoring Service
Tracks application performance metrics and generates insights
"""

import os
import logging
import time
import psutil
from typing import Dict, List, Optional, Callable
from datetime import datetime, timedelta
from functools import wraps

logger = logging.getLogger(__name__)

# Configuration
ENABLE_PERFORMANCE_MONITORING = os.getenv("ENABLE_PERFORMANCE_MONITORING", "true").lower() == "true"
SLOW_QUERY_THRESHOLD_MS = int(os.getenv("SLOW_QUERY_THRESHOLD_MS", "1000"))  # 1 second
SLOW_API_THRESHOLD_MS = int(os.getenv("SLOW_API_THRESHOLD_MS", "500"))  # 500ms


class PerformanceMonitorService:
    """
    Performance Monitoring Service
    Tracks and analyzes application performance
    """

    def __init__(self):
        """Initialize performance monitor"""
        self.enabled = ENABLE_PERFORMANCE_MONITORING
        self.slow_query_threshold = SLOW_QUERY_THRESHOLD_MS
        self.slow_api_threshold = SLOW_API_THRESHOLD_MS

    # ===========================
    # PERFORMANCE TRACKING
    # ===========================

    def track_metric(
        self,
        metric_type: str,
        endpoint: Optional[str] = None,
        response_time_ms: Optional[int] = None,
        database_time_ms: Optional[int] = None,
        external_api_time_ms: Optional[int] = None,
        total_time_ms: Optional[int] = None,
        user_id: Optional[int] = None,
        status_code: Optional[int] = None,
        metadata: Optional[Dict] = None
    ) -> None:
        """
        Track a performance metric

        Args:
            metric_type: Type of metric
            endpoint: API endpoint or operation name
            response_time_ms: Response time in milliseconds
            database_time_ms: Database query time
            external_api_time_ms: External API call time
            total_time_ms: Total operation time
            user_id: User ID (if applicable)
            status_code: HTTP status code
            metadata: Additional metadata
        """
        if not self.enabled:
            return

        try:
            from database.session import get_db
            from models.audit_log import PerformanceMetric

            # Get system metrics
            memory_mb = int(psutil.Process().memory_info().rss / 1024 / 1024)
            cpu_percent = int(psutil.Process().cpu_percent(interval=0.1))

            db = next(get_db())

            metric = PerformanceMetric(
                metric_type=metric_type,
                endpoint=endpoint,
                response_time_ms=response_time_ms,
                database_time_ms=database_time_ms,
                external_api_time_ms=external_api_time_ms,
                total_time_ms=total_time_ms or response_time_ms,
                memory_mb=memory_mb,
                cpu_percent=cpu_percent,
                user_id=user_id,
                status_code=status_code,
                metadata=metadata or {}
            )

            db.add(metric)
            db.commit()

            # Log slow operations
            if total_time_ms and total_time_ms > self.slow_api_threshold:
                logger.warning(
                    f"Slow operation detected: {endpoint} took {total_time_ms}ms "
                    f"(threshold: {self.slow_api_threshold}ms)"
                )

        except Exception as e:
            logger.error(f"Failed to track performance metric: {e}")

    def measure_api_request(self):
        """
        Decorator to measure API request performance

        Usage:
            @performance_monitor.measure_api_request()
            async def get_users(request: Request):
                # ... implementation
        """
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            async def async_wrapper(*args, **kwargs):
                if not self.enabled:
                    return await func(*args, **kwargs)

                start_time = time.time()
                status_code = 200
                user_id = None
                request_id = None

                try:
                    # Execute function
                    result = await func(*args, **kwargs)

                    # Extract status code from response
                    if hasattr(result, 'status_code'):
                        status_code = result.status_code

                    # Extract user ID from request if available
                    if args and hasattr(args[0], 'state'):
                        user_id = getattr(args[0].state, 'user_id', None)
                        request_id = getattr(args[0].state, 'request_id', None)

                    return result

                except Exception as e:
                    status_code = 500
                    raise

                finally:
                    # Calculate duration
                    duration_ms = int((time.time() - start_time) * 1000)

                    # Track metric
                    self.track_metric(
                        metric_type="api_response_time",
                        endpoint=f"{func.__module__}.{func.__name__}",
                        total_time_ms=duration_ms,
                        user_id=user_id,
                        status_code=status_code,
                        metadata={
                            "function": func.__name__,
                            "request_id": request_id
                        }
                    )

            @wraps(func)
            def sync_wrapper(*args, **kwargs):
                if not self.enabled:
                    return func(*args, **kwargs)

                start_time = time.time()
                status_code = 200
                user_id = None

                try:
                    result = func(*args, **kwargs)
                    return result

                except Exception as e:
                    status_code = 500
                    raise

                finally:
                    duration_ms = int((time.time() - start_time) * 1000)

                    self.track_metric(
                        metric_type="api_response_time",
                        endpoint=f"{func.__module__}.{func.__name__}",
                        total_time_ms=duration_ms,
                        user_id=user_id,
                        status_code=status_code,
                        metadata={"function": func.__name__}
                    )

            # Return appropriate wrapper based on function type
            import asyncio
            if asyncio.iscoroutinefunction(func):
                return async_wrapper
            else:
                return sync_wrapper

        return decorator

    def measure_database_query(self, query_name: str):
        """
        Decorator to measure database query performance

        Args:
            query_name: Name of the query

        Usage:
            @performance_monitor.measure_database_query("get_user_by_id")
            def get_user(user_id: int):
                # ... implementation
        """
        def decorator(func: Callable) -> Callable:
            @wraps(func)
            def wrapper(*args, **kwargs):
                if not self.enabled:
                    return func(*args, **kwargs)

                start_time = time.time()

                try:
                    result = func(*args, **kwargs)
                    return result

                finally:
                    duration_ms = int((time.time() - start_time) * 1000)

                    self.track_metric(
                        metric_type="database_query",
                        endpoint=query_name,
                        database_time_ms=duration_ms,
                        total_time_ms=duration_ms,
                        metadata={
                            "function": func.__name__,
                            "query": query_name
                        }
                    )

                    # Log slow queries
                    if duration_ms > self.slow_query_threshold:
                        logger.warning(
                            f"Slow query detected: {query_name} took {duration_ms}ms "
                            f"(threshold: {self.slow_query_threshold}ms)"
                        )

            return wrapper
        return decorator

    # ===========================
    # PERFORMANCE ANALYTICS
    # ===========================

    def get_api_performance_stats(self, endpoint: Optional[str] = None, hours: int = 24) -> Dict:
        """
        Get API performance statistics

        Args:
            endpoint: Specific endpoint (optional)
            hours: Number of hours to analyze

        Returns:
            Performance statistics
        """
        try:
            from database.session import get_db
            from models.audit_log import PerformanceMetric
            from sqlalchemy import func

            db = next(get_db())

            # Calculate start time
            start_time = datetime.utcnow() - timedelta(hours=hours)

            # Build query
            query = db.query(PerformanceMetric).filter(
                PerformanceMetric.metric_type == "api_response_time",
                PerformanceMetric.created_at >= start_time
            )

            if endpoint:
                query = query.filter(PerformanceMetric.endpoint == endpoint)

            metrics = query.all()

            if not metrics:
                return {
                    "endpoint": endpoint or "all",
                    "period_hours": hours,
                    "total_requests": 0,
                    "average_response_time_ms": 0,
                    "median_response_time_ms": 0,
                    "p95_response_time_ms": 0,
                    "p99_response_time_ms": 0,
                    "min_response_time_ms": 0,
                    "max_response_time_ms": 0,
                }

            # Calculate statistics
            response_times = sorted([m.total_time_ms for m in metrics if m.total_time_ms])

            total_requests = len(metrics)
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0

            # Calculate percentiles
            def percentile(data, p):
                if not data:
                    return 0
                k = (len(data) - 1) * p / 100
                f = int(k)
                c = int(k) + 1 if k < len(data) - 1 else int(k)
                return data[f] + (k - f) * (data[c] - data[f])

            median = percentile(response_times, 50)
            p95 = percentile(response_times, 95)
            p99 = percentile(response_times, 99)

            # Status code breakdown
            status_codes = {}
            for m in metrics:
                if m.status_code:
                    status_codes[m.status_code] = status_codes.get(m.status_code, 0) + 1

            # Slow requests
            slow_requests = sum(1 for rt in response_times if rt > self.slow_api_threshold)

            return {
                "endpoint": endpoint or "all",
                "period_hours": hours,
                "total_requests": total_requests,
                "average_response_time_ms": int(avg_response_time),
                "median_response_time_ms": int(median),
                "p95_response_time_ms": int(p95),
                "p99_response_time_ms": int(p99),
                "min_response_time_ms": min(response_times) if response_times else 0,
                "max_response_time_ms": max(response_times) if response_times else 0,
                "slow_requests": slow_requests,
                "slow_request_percentage": round((slow_requests / total_requests) * 100, 2) if total_requests > 0 else 0,
                "status_codes": status_codes,
            }

        except Exception as e:
            logger.error(f"Failed to get API performance stats: {e}")
            return {"error": str(e)}

    def get_database_performance_stats(self, hours: int = 24) -> Dict:
        """
        Get database performance statistics

        Args:
            hours: Number of hours to analyze

        Returns:
            Database performance statistics
        """
        try:
            from database.session import get_db
            from models.audit_log import PerformanceMetric

            db = next(get_db())

            start_time = datetime.utcnow() - timedelta(hours=hours)

            metrics = db.query(PerformanceMetric).filter(
                PerformanceMetric.metric_type == "database_query",
                PerformanceMetric.created_at >= start_time
            ).all()

            if not metrics:
                return {
                    "period_hours": hours,
                    "total_queries": 0,
                    "average_query_time_ms": 0,
                }

            query_times = [m.database_time_ms for m in metrics if m.database_time_ms]

            total_queries = len(metrics)
            avg_query_time = sum(query_times) / len(query_times) if query_times else 0

            # Slow queries
            slow_queries = sum(1 for qt in query_times if qt > self.slow_query_threshold)

            # Group by endpoint
            by_endpoint = {}
            for m in metrics:
                if m.endpoint:
                    if m.endpoint not in by_endpoint:
                        by_endpoint[m.endpoint] = []
                    if m.database_time_ms:
                        by_endpoint[m.endpoint].append(m.database_time_ms)

            # Find slowest queries
            slowest_queries = sorted(
                [
                    {
                        "endpoint": endpoint,
                        "average_time_ms": int(sum(times) / len(times)),
                        "max_time_ms": max(times),
                        "count": len(times)
                    }
                    for endpoint, times in by_endpoint.items()
                ],
                key=lambda x: x["average_time_ms"],
                reverse=True
            )[:10]

            return {
                "period_hours": hours,
                "total_queries": total_queries,
                "average_query_time_ms": int(avg_query_time),
                "min_query_time_ms": min(query_times) if query_times else 0,
                "max_query_time_ms": max(query_times) if query_times else 0,
                "slow_queries": slow_queries,
                "slow_query_percentage": round((slow_queries / total_queries) * 100, 2) if total_queries > 0 else 0,
                "slowest_queries": slowest_queries,
            }

        except Exception as e:
            logger.error(f"Failed to get database performance stats: {e}")
            return {"error": str(e)}

    def get_system_resource_stats(self, hours: int = 24) -> Dict:
        """
        Get system resource usage statistics

        Args:
            hours: Number of hours to analyze

        Returns:
            System resource statistics
        """
        try:
            from database.session import get_db
            from models.audit_log import PerformanceMetric

            db = next(get_db())

            start_time = datetime.utcnow() - timedelta(hours=hours)

            metrics = db.query(PerformanceMetric).filter(
                PerformanceMetric.created_at >= start_time
            ).all()

            if not metrics:
                return {
                    "period_hours": hours,
                    "average_memory_mb": 0,
                    "average_cpu_percent": 0,
                }

            # Filter out None values
            memory_values = [m.memory_mb for m in metrics if m.memory_mb is not None]
            cpu_values = [m.cpu_percent for m in metrics if m.cpu_percent is not None]

            # Get current system stats
            current_memory = psutil.virtual_memory()
            current_disk = psutil.disk_usage('/')

            return {
                "period_hours": hours,
                "average_memory_mb": int(sum(memory_values) / len(memory_values)) if memory_values else 0,
                "peak_memory_mb": max(memory_values) if memory_values else 0,
                "average_cpu_percent": int(sum(cpu_values) / len(cpu_values)) if cpu_values else 0,
                "peak_cpu_percent": max(cpu_values) if cpu_values else 0,
                "current_system": {
                    "total_memory_gb": round(current_memory.total / 1024 / 1024 / 1024, 2),
                    "available_memory_gb": round(current_memory.available / 1024 / 1024 / 1024, 2),
                    "memory_percent": current_memory.percent,
                    "disk_total_gb": round(current_disk.total / 1024 / 1024 / 1024, 2),
                    "disk_used_gb": round(current_disk.used / 1024 / 1024 / 1024, 2),
                    "disk_percent": current_disk.percent,
                }
            }

        except Exception as e:
            logger.error(f"Failed to get system resource stats: {e}")
            return {"error": str(e)}

    # ===========================
    # PERFORMANCE ALERTS
    # ===========================

    def check_performance_thresholds(self) -> List[Dict]:
        """
        Check if performance metrics exceed thresholds

        Returns:
            List of performance alerts
        """
        alerts = []

        try:
            # Check API performance
            api_stats = self.get_api_performance_stats(hours=1)  # Last hour

            if api_stats.get("p95_response_time_ms", 0) > self.slow_api_threshold:
                alerts.append({
                    "type": "slow_api",
                    "severity": "warning",
                    "message": f"API P95 response time is {api_stats['p95_response_time_ms']}ms (threshold: {self.slow_api_threshold}ms)",
                    "metrics": api_stats
                })

            # Check database performance
            db_stats = self.get_database_performance_stats(hours=1)

            if db_stats.get("average_query_time_ms", 0) > self.slow_query_threshold:
                alerts.append({
                    "type": "slow_database",
                    "severity": "warning",
                    "message": f"Average database query time is {db_stats['average_query_time_ms']}ms (threshold: {self.slow_query_threshold}ms)",
                    "metrics": db_stats
                })

            # Check system resources
            memory = psutil.virtual_memory()
            if memory.percent > 90:
                alerts.append({
                    "type": "high_memory",
                    "severity": "critical",
                    "message": f"Memory usage is {memory.percent}% (threshold: 90%)",
                    "metrics": {"memory_percent": memory.percent}
                })

            disk = psutil.disk_usage('/')
            if disk.percent > 90:
                alerts.append({
                    "type": "high_disk",
                    "severity": "critical",
                    "message": f"Disk usage is {disk.percent}% (threshold: 90%)",
                    "metrics": {"disk_percent": disk.percent}
                })

        except Exception as e:
            logger.error(f"Failed to check performance thresholds: {e}")

        return alerts


# Singleton instance
_performance_monitor: Optional[PerformanceMonitorService] = None


def get_performance_monitor() -> PerformanceMonitorService:
    """Get performance monitor instance"""
    global _performance_monitor
    if _performance_monitor is None:
        _performance_monitor = PerformanceMonitorService()
    return _performance_monitor
