"""
SecureWave VPN - Email Service
Handles sending transactional emails for verification, password reset, and notifications
"""

import logging
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional, Dict

from config.settings import get_settings

logger = logging.getLogger(__name__)


class EmailService:
    """
    Production-grade email service
    Sends transactional emails with proper error handling and logging
    """

    def __init__(self):
        """Initialize email service"""
        settings = get_settings(refresh=True)
        self.provider = settings.email_provider
        self.smtp_host = settings.smtp_host
        self.smtp_port = settings.smtp_port
        self.smtp_user = settings.smtp_user
        self.smtp_password = settings.smtp_password
        self.from_email = settings.from_email
        self.from_name = settings.from_name
        self.sendgrid_api_key = settings.sendgrid_api_key
        self.aws_ses_region = settings.aws_ses_region
        self.app_url = settings.app_url
        self.enabled = self._provider_ready()
        if not self.enabled:
            logger.warning("Email provider not configured - Email functionality disabled")

    def config_status(self) -> Dict[str, object]:
        """Return provider configuration status without sending email."""
        missing = []
        provider = self.provider

        def require(name: str, value: Optional[str]) -> None:
            if not value:
                missing.append(name)

        if provider == "smtp":
            require("SMTP_HOST", self.smtp_host)
            require("SMTP_PORT", str(self.smtp_port))
            require("SMTP_USER", self.smtp_user)
            require("SMTP_PASSWORD", self.smtp_password)
            require("FROM_EMAIL", self.from_email)
        elif provider == "sendgrid":
            require("SENDGRID_API_KEY", self.sendgrid_api_key)
            require("FROM_EMAIL", self.from_email)
        elif provider in ("ses", "aws_ses"):
            require("FROM_EMAIL", self.from_email)
            require("AWS_SES_REGION", self.aws_ses_region)
        else:
            missing.append(f"EMAIL_PROVIDER({provider})")

        return {
            "provider": provider,
            "enabled": self.enabled,
            "missing": missing,
            "from_email": self.from_email,
            "from_name": self.from_name,
            "smtp_host": self.smtp_host if provider == "smtp" else None,
            "smtp_port": self.smtp_port if provider == "smtp" else None,
        }

    def send_email(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str] = None
    ) -> bool:
        """
        Send email via SMTP

        Args:
            to_email: Recipient email address
            subject: Email subject
            html_content: HTML email content
            text_content: Plain text fallback (optional)

        Returns:
            True if successful, False otherwise
        """
        if not self.enabled:
            logger.warning(f"Email service disabled - Would send: {subject} to {to_email}")
            return False

        try:
            if self.provider == "smtp":
                success = self._send_via_smtp(to_email, subject, html_content, text_content)
            elif self.provider == "sendgrid":
                success = self._send_via_sendgrid(to_email, subject, html_content, text_content)
            elif self.provider in ("ses", "aws_ses"):
                success = self._send_via_ses(to_email, subject, html_content, text_content)
            else:
                logger.error(f"Unknown email provider: {self.provider}")
                return False

            if success:
                logger.info(f"✓ Email sent successfully: {subject} to {to_email}")
            else:
                logger.error(f"✗ Failed to send email to {to_email}")
            return success

        except Exception as e:
            logger.error(f"✗ Failed to send email to {to_email}: {e}")
            return False

    def _provider_ready(self) -> bool:
        if self.provider == "smtp":
            return bool(self.smtp_user and self.smtp_password and self.from_email)
        if self.provider == "sendgrid":
            return bool(self.sendgrid_api_key and self.from_email)
        if self.provider in ("ses", "aws_ses"):
            return bool(self.from_email)
        logger.error(f"Unknown email provider: {self.provider}")
        return False

    def _send_via_smtp(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str],
    ) -> bool:
        message = MIMEMultipart("alternative")
        message["Subject"] = subject
        message["From"] = f"{self.from_name} <{self.from_email}>"
        message["To"] = to_email

        if text_content:
            message.attach(MIMEText(text_content, "plain"))
        message.attach(MIMEText(html_content, "html"))

        with smtplib.SMTP(self.smtp_host, self.smtp_port) as server:
            server.starttls()
            server.login(self.smtp_user, self.smtp_password)
            server.sendmail(self.from_email, to_email, message.as_string())
        return True

    def _send_via_sendgrid(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str],
    ) -> bool:
        if not self.sendgrid_api_key:
            logger.error("SENDGRID_API_KEY not configured")
            return False
        try:
            from sendgrid import SendGridAPIClient
            from sendgrid.helpers.mail import Mail, Email, To, Content
        except ImportError as exc:
            logger.error(f"SendGrid SDK not installed: {exc}")
            return False

        mail = Mail(
            from_email=Email(self.from_email, self.from_name),
            to_emails=To(to_email),
            subject=subject,
            html_content=Content("text/html", html_content),
        )
        if text_content:
            mail.add_content(Content("text/plain", text_content))

        client = SendGridAPIClient(self.sendgrid_api_key)
        response = client.send(mail)
        return 200 <= response.status_code < 300

    def _send_via_ses(
        self,
        to_email: str,
        subject: str,
        html_content: str,
        text_content: Optional[str],
    ) -> bool:
        try:
            import boto3
        except ImportError as exc:
            logger.error(f"boto3 not installed: {exc}")
            return False

        client = boto3.client("ses", region_name=self.aws_ses_region)
        body = {"Html": {"Data": html_content}}
        if text_content:
            body["Text"] = {"Data": text_content}
        response = client.send_email(
            Source=f"{self.from_name} <{self.from_email}>",
            Destination={"ToAddresses": [to_email]},
            Message={
                "Subject": {"Data": subject},
                "Body": body,
            },
        )
        return "MessageId" in response

    def send_verification_email(
        self,
        to_email: str,
        verification_token: str,
        user_name: Optional[str] = None
    ) -> bool:
        """
        Send email verification link

        Args:
            to_email: User's email address
            verification_token: Verification token
            user_name: User's name (optional)

        Returns:
            True if successful
        """
        verification_url = f"{self.app_url}/verify-email?token={verification_token}"

        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Welcome to SecureWave VPN!</h1>
        </div>
        <div class="content">
            <p>Hi{' ' + user_name if user_name else ''},</p>
            <p>Thank you for registering with SecureWave VPN. Please verify your email address to activate your account.</p>
            <p style="text-align: center;">
                <a href="{verification_url}" class="button">Verify Email Address</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #667eea;">{verification_url}</p>
            <p><strong>This link will expire in 24 hours.</strong></p>
            <p>If you didn't create an account with SecureWave VPN, please ignore this email.</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

        text_content = f"""
Welcome to SecureWave VPN!

Hi{' ' + user_name if user_name else ''},

Thank you for registering with SecureWave VPN. Please verify your email address to activate your account.

Verification Link:
{verification_url}

This link will expire in 24 hours.

If you didn't create an account with SecureWave VPN, please ignore this email.

---
SecureWave VPN
"""

        return self.send_email(
            to_email=to_email,
            subject="Verify Your Email - SecureWave VPN",
            html_content=html_content,
            text_content=text_content
        )

    def send_password_reset_email(
        self,
        to_email: str,
        reset_token: str,
        user_name: Optional[str] = None
    ) -> bool:
        """
        Send password reset link

        Args:
            to_email: User's email address
            reset_token: Password reset token
            user_name: User's name (optional)

        Returns:
            True if successful
        """
        reset_url = f"{APP_URL}/reset-password?token={reset_token}"

        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .button {{ display: inline-block; background: #667eea; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
        .warning {{ background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Password Reset Request</h1>
        </div>
        <div class="content">
            <p>Hi{' ' + user_name if user_name else ''},</p>
            <p>We received a request to reset your password for your SecureWave VPN account.</p>
            <p style="text-align: center;">
                <a href="{reset_url}" class="button">Reset Password</a>
            </p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all; color: #667eea;">{reset_url}</p>
            <div class="warning">
                <strong>Important:</strong>
                <ul>
                    <li>This link will expire in 15 minutes</li>
                    <li>This link can only be used once</li>
                    <li>If you didn't request this reset, please ignore this email and your password will remain unchanged</li>
                </ul>
            </div>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

        text_content = f"""
Password Reset Request

Hi{' ' + user_name if user_name else ''},

We received a request to reset your password for your SecureWave VPN account.

Reset Link:
{reset_url}

IMPORTANT:
- This link will expire in 15 minutes
- This link can only be used once
- If you didn't request this reset, please ignore this email

---
SecureWave VPN
"""

        return self.send_email(
            to_email=to_email,
            subject="Password Reset - SecureWave VPN",
            html_content=html_content,
            text_content=text_content
        )

    def send_2fa_enabled_email(
        self,
        to_email: str,
        user_name: Optional[str] = None
    ) -> bool:
        """
        Send notification that 2FA was enabled

        Args:
            to_email: User's email address
            user_name: User's name (optional)

        Returns:
            True if successful
        """
        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; padding: 30px; text-align: center; }}
        .content {{ background: #f9f9f9; padding: 30px; }}
        .footer {{ text-align: center; padding: 20px; color: #666; font-size: 12px; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Two-Factor Authentication Enabled</h1>
        </div>
        <div class="content">
            <p>Hi{' ' + user_name if user_name else ''},</p>
            <p>Two-factor authentication has been successfully enabled on your SecureWave VPN account.</p>
            <p>Your account is now more secure. You'll need to enter a verification code from your authenticator app each time you log in.</p>
            <p>If you didn't enable 2FA, please contact support immediately.</p>
        </div>
        <div class="footer">
            <p>&copy; 2024 SecureWave VPN. All rights reserved.</p>
        </div>
    </div>
</body>
</html>
"""

        return self.send_email(
            to_email=to_email,
            subject="Two-Factor Authentication Enabled - SecureWave VPN",
            html_content=html_content
        )

    def send_subscription_notification(
        self,
        to_email: str,
        notification_type: str,
        data: Dict
    ) -> bool:
        """
        Send subscription-related notifications

        Args:
            to_email: User's email address
            notification_type: Type of notification (created, canceled, payment_failed, etc.)
            data: Notification data

        Returns:
            True if successful
        """
        subject_map = {
            "created": "Subscription Activated - SecureWave VPN",
            "canceled": "Subscription Canceled - SecureWave VPN",
            "payment_failed": "Payment Failed - SecureWave VPN",
            "payment_succeeded": "Payment Received - SecureWave VPN",
            "trial_ending": "Trial Ending Soon - SecureWave VPN",
        }

        subject = subject_map.get(notification_type, "Subscription Update - SecureWave VPN")

        # Build content based on notification type
        # This is a simplified version - you can expand this with templates
        html_content = f"""
<!DOCTYPE html>
<html>
<body>
    <h2>{subject}</h2>
    <p>Your subscription status has been updated.</p>
    <p>Details: {data}</p>
</body>
</html>
"""

        return self.send_email(
            to_email=to_email,
            subject=subject,
            html_content=html_content
        )
