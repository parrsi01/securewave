from datetime import datetime
import os
import logging

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr, field_validator

from services.email_service import EmailService

router = APIRouter()
logger = logging.getLogger(__name__)

SUPPORT_INBOX = os.getenv("SUPPORT_INBOX") or os.getenv("SMTP_FROM_EMAIL") or "support@securewave.example.com"


class ContactRequest(BaseModel):
    name: str
    email: EmailStr
    subject: str
    message: str

    @field_validator('name')
    @classmethod
    def validate_name(cls, v):
        if not v or len(v.strip()) < 2:
            raise ValueError('Name must be at least 2 characters')
        if len(v) > 100:
            raise ValueError('Name must be less than 100 characters')
        return v.strip()

    @field_validator('subject')
    @classmethod
    def validate_subject(cls, v):
        if not v or len(v.strip()) < 3:
            raise ValueError('Subject must be at least 3 characters')
        if len(v) > 200:
            raise ValueError('Subject must be less than 200 characters')
        return v.strip()

    @field_validator('message')
    @classmethod
    def validate_message(cls, v):
        if not v or len(v.strip()) < 10:
            raise ValueError('Message must be at least 10 characters')
        if len(v) > 1000:
            raise ValueError('Message must be less than 1000 characters')
        return v.strip()


class ContactResponse(BaseModel):
    success: bool
    message: str
    timestamp: str


@router.post("/submit", response_model=ContactResponse)
def submit_contact_form(payload: ContactRequest):
    """
    Submit a contact form message

    In a production environment, this would:
    - Store the message in a database
    - Send an email notification to support team
    - Send a confirmation email to the user
    - Create a support ticket

    For now, it validates the input and returns success.
    """
    try:
        email_service = EmailService()
        if not email_service.enabled:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Contact service is temporarily unavailable. Please try again later."
            )
        support_subject = f"[SecureWave] {payload.subject}"
        support_html = f"""
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #1F2937;">
            <h2>New Contact Request</h2>
            <p><strong>Name:</strong> {payload.name}</p>
            <p><strong>Email:</strong> {payload.email}</p>
            <p><strong>Message:</strong></p>
            <p>{payload.message}</p>
          </body>
        </html>
        """
        support_text = (
            f"New Contact Request\n\n"
            f"Name: {payload.name}\n"
            f"Email: {payload.email}\n"
            f"Subject: {payload.subject}\n\n"
            f"{payload.message}\n"
        )

        confirmation_subject = "We received your message"
        confirmation_html = f"""
        <html>
          <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #1F2937;">
            <h2>Thanks for reaching out</h2>
            <p>Hi {payload.name},</p>
            <p>We received your message and a SecureWave specialist will respond within 24 hours.</p>
            <p><strong>Your message:</strong></p>
            <p>{payload.message}</p>
          </body>
        </html>
        """
        confirmation_text = (
            f"Thanks for reaching out, {payload.name}.\n\n"
            "We received your message and will respond within 24 hours.\n\n"
            f"Your message:\n{payload.message}\n"
        )

        email_service.send_email(
            to_email=SUPPORT_INBOX,
            subject=support_subject,
            html_content=support_html,
            text_content=support_text,
        )
        email_service.send_email(
            to_email=payload.email,
            subject=confirmation_subject,
            html_content=confirmation_html,
            text_content=confirmation_text,
        )

        logger.info(
            "Contact form submission processed",
            extra={"email": payload.email, "subject": payload.subject},
        )

        return ContactResponse(
            success=True,
            message="Thank you for contacting us! We'll get back to you within 24 hours.",
            timestamp=datetime.utcnow().isoformat()
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to submit contact form", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to submit contact form. Please try again later."
        )
