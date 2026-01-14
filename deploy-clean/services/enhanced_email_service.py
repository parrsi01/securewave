"""
SecureWave VPN - Enhanced Email Service
Multi-provider email service with SendGrid, AWS SES, and SMTP support
"""

import os
import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional, Dict, List
from datetime import datetime
from dotenv import load_dotenv
from jinja2 import Template

load_dotenv()
load_dotenv(".env.production")

logger = logging.getLogger(__name__)

# Email configuration
EMAIL_PROVIDER = os.getenv("EMAIL_PROVIDER", "smtp")  # smtp, sendgrid, aws_ses
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SENDGRID_API_KEY = os.getenv("SENDGRID_API_KEY")
AWS_SES_REGION = os.getenv("AWS_SES_REGION", "us-east-1")
FROM_EMAIL = os.getenv("FROM_EMAIL", SMTP_USER)
FROM_NAME = os.getenv("FROM_NAME", "SecureWave VPN")
APP_URL = os.getenv("APP_URL", "https://securewave.example.com")


class EnhancedEmailService:
    """
    Production-grade multi-provider email service
    Supports SMTP, SendGrid, and AWS SES with comprehensive tracking
    """

    def __init__(self, db_session=None):
        """Initialize email service"""
        self.db = db_session
        self.provider = EMAIL_PROVIDER.lower()
        self.enabled = self._check_provider_config()

        if not self.enabled:
            logger.warning(f"Email service disabled - provider '{self.provider}' not configured")

    def _check_provider_config(self) -> bool:
        """Check if provider is properly configured"""
        if self.provider == "smtp":
            return SMTP_USER and SMTP_PASSWORD
        elif self.provider == "sendgrid":
            return SENDGRID_API_KEY is not None
        elif self.provider == "aws_ses":
            # AWS SES uses boto3 with environment credentials
            try:
                import boto3
                return True
            except ImportError:
                logger.error("boto3 not installed - required for AWS SES")
                return False
        return False

    # ===========================
    # CORE EMAIL SENDING
    # ===========================

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None,
        template_name: Optional[str] = None,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        metadata: Optional[Dict] = None
    ) -> bool:
        """
        Send email via configured provider

        Args:
            to_email: Recipient email
            subject: Email subject
            html_content: HTML content
            text_content: Plain text content (optional)
            template_name: Template identifier (for tracking)
            user_id: User ID (for tracking)
            category: Email category (for tracking)
            metadata: Additional metadata

        Returns:
            True if successful
        """
        if not self.enabled:
            logger.warning(f"Email not sent - service disabled: {subject} to {to_email}")
            return False

        try:
            # Send via appropriate provider
            if self.provider == "smtp":
                success, message_id = self._send_via_smtp(to_email, subject, html_content, text_content)
            elif self.provider == "sendgrid":
                success, message_id = self._send_via_sendgrid(to_email, subject, html_content, text_content)
            elif self.provider == "aws_ses":
                success, message_id = self._send_via_ses(to_email, subject, html_content, text_content)
            else:
                logger.error(f"Unknown email provider: {self.provider}")
                return False

            # Log email
            if self.db:
                self._log_email(
                    to_email=to_email,
                    subject=subject,
                    template_name=template_name,
                    user_id=user_id,
                    category=category,
                    status="sent" if success else "failed",
                    provider_message_id=message_id,
                    metadata=metadata
                )

            if success:
                logger.info(f"✓ Email sent via {self.provider}: {subject} to {to_email}")
            else:
                logger.error(f"✗ Email failed via {self.provider}: {subject} to {to_email}")

            return success

        except Exception as e:
            logger.error(f"✗ Email error: {e}")
            if self.db:
                self._log_email(
                    to_email=to_email,
                    subject=subject,
                    template_name=template_name,
                    user_id=user_id,
                    category=category,
                    status="failed",
                    error_message=str(e),
                    metadata=metadata
                )
            return False

    # ===========================
    # PROVIDER IMPLEMENTATIONS
    # ===========================

    def _send_via_smtp(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None
    ) -> tuple[bool, Optional[str]]:
        """Send email via SMTP"""
        try:
            message = MIMEMultipart("alternative")
            message["Subject"] = subject
            message["From"] = f"{FROM_NAME} <{FROM_EMAIL}>"
            message["To"] = to_email

            if text_content:
                part1 = MIMEText(text_content, "plain")
                message.attach(part1)

            part2 = MIMEText(html_content, "html")
            message.attach(part2)

            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
                server.starttls()
                server.login(SMTP_USER, SMTP_PASSWORD)
                server.sendmail(FROM_EMAIL, to_email, message.as_string())

            return True, None

        except Exception as e:
            logger.error(f"SMTP error: {e}")
            return False, None

    def _send_via_sendgrid(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None
    ) -> tuple[bool, Optional[str]]:
        """Send email via SendGrid"""
        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail, Email, To, Content

            message = Mail(
                from_email=Email(FROM_EMAIL, FROM_NAME),
                to_emails=To(to_email),
                subject=subject,
                html_content=Content("text/html", html_content)
            )

            if text_content:
                message.plain_text_content = Content("text/plain", text_content)

            sg = SendGridAPIClient(SENDGRID_API_KEY)
            response = sg.send(message)

            # Extract message ID from headers
            message_id = response.headers.get('X-Message-Id')

            return response.status_code in [200, 201, 202], message_id

        except ImportError:
            logger.error("sendgrid package not installed - run: pip install sendgrid")
            return False, None
        except Exception as e:
            logger.error(f"SendGrid error: {e}")
            return False, None

    def _send_via_ses(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None
    ) -> tuple[bool, Optional[str]]:
        """Send email via AWS SES"""
        try:
            import boto3

            client = boto3.client('ses', region_name=AWS_SES_REGION)

            body = {"Html": {"Charset": "UTF-8", "Data": html_content}}
            if text_content:
                body["Text"] = {"Charset": "UTF-8", "Data": text_content}

            response = client.send_email(
                Source=f"{FROM_NAME} <{FROM_EMAIL}>",
                Destination={"ToAddresses": [to_email]},
                Message={
                    "Subject": {"Charset": "UTF-8", "Data": subject},
                    "Body": body
                }
            )

            message_id = response.get('MessageId')
            return True, message_id

        except ImportError:
            logger.error("boto3 not installed - run: pip install boto3")
            return False, None
        except Exception as e:
            logger.error(f"AWS SES error: {e}")
            return False, None

    # ===========================
    # EMAIL LOGGING
    # ===========================

    def _log_email(
        self,
        to_email: str,
        subject: str,
        status: str,
        template_name: Optional[str] = None,
        user_id: Optional[int] = None,
        category: Optional[str] = None,
        provider_message_id: Optional[str] = None,
        error_message: Optional[str] = None,
        metadata: Optional[Dict] = None
    ):
        """Log email to database"""
        try:
            from models.email_log import EmailLog

            log = EmailLog(
                user_id=user_id,
                to_email=to_email,
                from_email=FROM_EMAIL,
                subject=subject,
                template_name=template_name,
                email_type="transactional",
                category=category or "general",
                provider=self.provider,
                provider_message_id=provider_message_id,
                status=status,
                error_message=error_message,
                metadata=metadata,
                sent_at=datetime.utcnow() if status == "sent" else None,
                failed_at=datetime.utcnow() if status == "failed" else None,
            )

            self.db.add(log)
            self.db.commit()

        except Exception as e:
            logger.error(f"Failed to log email: {e}")
            self.db.rollback()

    # ===========================
    # TEMPLATE RENDERING
    # ===========================

    def render_template(self, template_html: str, variables: Dict) -> str:
        """Render Jinja2 template"""
        template = Template(template_html)
        return template.render(**variables)

    # ===========================
    # TRANSACTIONAL EMAILS
    # ===========================

    def send_welcome_email(self, to_email: str, user_name: Optional[str] = None, user_id: Optional[int] = None) -> bool:
        """Send welcome email to new user"""
        variables = {
            "user_name": user_name or to_email.split('@')[0],
            "app_url": APP_URL,
            "login_url": f"{APP_URL}/login",
            "dashboard_url": f"{APP_URL}/dashboard",
        }

        html_content = self._get_welcome_email_html(variables)
        text_content = self._get_welcome_email_text(variables)

        return self.send_email(
            to_email=to_email,
            subject="Welcome to SecureWave VPN!",
            html_content=html_content,
            text_content=text_content,
            template_name="welcome_email",
            user_id=user_id,
            category="account"
        )

    def send_subscription_expiring_email(
        self,
        to_email: str,
        user_name: Optional[str] = None,
        days_remaining: int = 7,
        subscription_plan: str = "Premium",
        renewal_url: Optional[str] = None,
        user_id: Optional[int] = None
    ) -> bool:
        """Send subscription expiration notice"""
        variables = {
            "user_name": user_name or to_email.split('@')[0],
            "days_remaining": days_remaining,
            "subscription_plan": subscription_plan,
            "renewal_url": renewal_url or f"{APP_URL}/billing",
            "app_url": APP_URL,
        }

        html_content = self._get_subscription_expiring_html(variables)
        text_content = self._get_subscription_expiring_text(variables)

        return self.send_email(
            to_email=to_email,
            subject=f"Your {subscription_plan} subscription expires in {days_remaining} days",
            html_content=html_content,
            text_content=text_content,
            template_name="subscription_expiring",
            user_id=user_id,
            category="billing"
        )

    def send_subscription_expired_email(
        self,
        to_email: str,
        user_name: Optional[str] = None,
        subscription_plan: str = "Premium",
        renewal_url: Optional[str] = None,
        user_id: Optional[int] = None
    ) -> bool:
        """Send subscription expired notice"""
        variables = {
            "user_name": user_name or to_email.split('@')[0],
            "subscription_plan": subscription_plan,
            "renewal_url": renewal_url or f"{APP_URL}/billing",
            "app_url": APP_URL,
        }

        html_content = self._get_subscription_expired_html(variables)
        text_content = self._get_subscription_expired_text(variables)

        return self.send_email(
            to_email=to_email,
            subject=f"Your {subscription_plan} subscription has expired",
            html_content=html_content,
            text_content=text_content,
            template_name="subscription_expired",
            user_id=user_id,
            category="billing"
        )

    def send_subscription_renewed_email(
        self,
        to_email: str,
        user_name: Optional[str] = None,
        subscription_plan: str = "Premium",
        next_billing_date: Optional[str] = None,
        amount: float = 0.0,
        user_id: Optional[int] = None
    ) -> bool:
        """Send subscription renewal confirmation"""
        variables = {
            "user_name": user_name or to_email.split('@')[0],
            "subscription_plan": subscription_plan,
            "next_billing_date": next_billing_date,
            "amount": f"${amount:.2f}",
            "dashboard_url": f"{APP_URL}/dashboard",
            "app_url": APP_URL,
        }

        html_content = self._get_subscription_renewed_html(variables)
        text_content = self._get_subscription_renewed_text(variables)

        return self.send_email(
            to_email=to_email,
            subject=f"Your {subscription_plan} subscription has been renewed",
            html_content=html_content,
            text_content=text_content,
            template_name="subscription_renewed",
            user_id=user_id,
            category="billing"
        )

    # ===========================
    # EMAIL TEMPLATES (HTML)
    # ===========================

    def _get_welcome_email_html(self, vars: Dict) -> str:
        """Welcome email HTML template"""
        return f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .features {{ background: white; padding: 20px; margin: 20px 0; border-radius: 5px; }}
        .feature {{ margin: 10px 0; padding: 10px; border-left: 3px solid #667eea; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Welcome to SecureWave VPN!</h1>
        </div>
        <div class="content">
            <p>Hi {vars['user_name']},</p>
            <p>Thank you for joining SecureWave VPN! We're excited to help you browse securely and privately.</p>

            <div class="features">
                <h3>What's Next?</h3>
                <div class="feature">
                    <strong>1. Download Configuration</strong><br>
                    Get your VPN configuration from the dashboard
                </div>
                <div class="feature">
                    <strong>2. Connect to a Server</strong><br>
                    Choose from our global network of VPN servers
                </div>
                <div class="feature">
                    <strong>3. Browse Securely</strong><br>
                    Enjoy encrypted, private internet access
                </div>
            </div>

            <p style="text-align: center;">
                <a href="{vars['dashboard_url']}" class="button">Go to Dashboard</a>
            </p>

            <p>If you have any questions, our support team is here to help!</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

    def _get_welcome_email_text(self, vars: Dict) -> str:
        """Welcome email plain text template"""
        return f"""
Welcome to SecureWave VPN!

Hi {vars['user_name']},

Thank you for joining SecureWave VPN! We're excited to help you browse securely and privately.

What's Next?

1. Download Configuration
   Get your VPN configuration from the dashboard

2. Connect to a Server
   Choose from our global network of VPN servers

3. Browse Securely
   Enjoy encrypted, private internet access

Get Started: {vars['dashboard_url']}

If you have any questions, our support team is here to help!

---
SecureWave VPN
{vars['app_url']}
"""

    def _get_subscription_expiring_html(self, vars: Dict) -> str:
        """Subscription expiring HTML template"""
        return f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .warning {{ background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Subscription Expiring Soon</h1>
        </div>
        <div class="content">
            <p>Hi {vars['user_name']},</p>
            <p>Your <strong>{vars['subscription_plan']}</strong> subscription will expire in <strong>{vars['days_remaining']} days</strong>.</p>

            <div class="warning">
                <strong>Don't lose access!</strong><br>
                Renew now to continue enjoying secure, private browsing without interruption.
            </div>

            <p style="text-align: center;">
                <a href="{vars['renewal_url']}" class="button">Renew Subscription</a>
            </p>

            <p>Need help? Contact our support team anytime.</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

    def _get_subscription_expiring_text(self, vars: Dict) -> str:
        """Subscription expiring plain text template"""
        return f"""
Subscription Expiring Soon

Hi {vars['user_name']},

Your {vars['subscription_plan']} subscription will expire in {vars['days_remaining']} days.

Don't lose access! Renew now to continue enjoying secure, private browsing without interruption.

Renew Now: {vars['renewal_url']}

Need help? Contact our support team anytime.

---
SecureWave VPN
{vars['app_url']}
"""

    def _get_subscription_expired_html(self, vars: Dict) -> str:
        """Subscription expired HTML template"""
        return f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .alert {{ background: #fee2e2; border-left: 4px solid #ef4444; padding: 15px; margin: 20px 0; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Subscription Expired</h1>
        </div>
        <div class="content">
            <p>Hi {vars['user_name']},</p>
            <p>Your <strong>{vars['subscription_plan']}</strong> subscription has expired.</p>

            <div class="alert">
                <strong>Your VPN access has been suspended.</strong><br>
                Renew your subscription to restore full access to SecureWave VPN.
            </div>

            <p style="text-align: center;">
                <a href="{vars['renewal_url']}" class="button">Renew Now</a>
            </p>

            <p>Questions? Our support team is ready to assist you.</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

    def _get_subscription_expired_text(self, vars: Dict) -> str:
        """Subscription expired plain text template"""
        return f"""
Subscription Expired

Hi {vars['user_name']},

Your {vars['subscription_plan']} subscription has expired.

Your VPN access has been suspended. Renew your subscription to restore full access to SecureWave VPN.

Renew Now: {vars['renewal_url']}

Questions? Our support team is ready to assist you.

---
SecureWave VPN
{vars['app_url']}
"""

    def _get_subscription_renewed_html(self, vars: Dict) -> str:
        """Subscription renewed HTML template"""
        return f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .success {{ background: #d1fae5; border-left: 4px solid #10b981; padding: 15px; margin: 20px 0; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Subscription Renewed!</h1>
        </div>
        <div class="content">
            <p>Hi {vars['user_name']},</p>
            <p>Your <strong>{vars['subscription_plan']}</strong> subscription has been successfully renewed.</p>

            <div class="success">
                <strong>Payment Confirmed:</strong> {vars['amount']}<br>
                <strong>Next Billing Date:</strong> {vars['next_billing_date']}
            </div>

            <p>Thank you for continuing to trust SecureWave VPN for your online security and privacy.</p>

            <p style="text-align: center;">
                <a href="{vars['dashboard_url']}" class="button">Go to Dashboard</a>
            </p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

    def _get_subscription_renewed_text(self, vars: Dict) -> str:
        """Subscription renewed plain text template"""
        return f"""
Subscription Renewed!

Hi {vars['user_name']},

Your {vars['subscription_plan']} subscription has been successfully renewed.

Payment Confirmed: {vars['amount']}
Next Billing Date: {vars['next_billing_date']}

Thank you for continuing to trust SecureWave VPN for your online security and privacy.

Dashboard: {vars['dashboard_url']}

---
SecureWave VPN
{vars['app_url']}
"""


def get_enhanced_email_service(db_session=None) -> EnhancedEmailService:
    """Get enhanced email service instance"""
    return EnhancedEmailService(db_session)
