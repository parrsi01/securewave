from datetime import datetime

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, EmailStr, field_validator

router = APIRouter()


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
        # TODO: In production, implement actual message handling:
        # - Store in database (ContactMessage model)
        # - Send email via SendGrid/AWS SES
        # - Create support ticket in ticketing system
        # - Send auto-reply to user

        # For now, just log the contact attempt (in production, use proper logging)
        print(f"Contact form submission received:")
        print(f"  Name: {payload.name}")
        print(f"  Email: {payload.email}")
        print(f"  Subject: {payload.subject}")
        print(f"  Message: {payload.message[:100]}...")

        return ContactResponse(
            success=True,
            message="Thank you for contacting us! We'll get back to you within 24 hours.",
            timestamp=datetime.utcnow().isoformat()
        )

    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to submit contact form: {str(e)}"
        )
