"""
SecureWave VPN - Support Ticket Service
Manage user support tickets and helpdesk system
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from models.user import User
from models.support_ticket import (
    SupportTicket,
    TicketMessage,
    TicketPriority,
    TicketStatus,
    TicketCategory
)
from services.email_service import EmailService

logger = logging.getLogger(__name__)

# SLA (Service Level Agreement) times in hours
SLA_RESPONSE_TIME = {
    TicketPriority.LOW: 48,
    TicketPriority.MEDIUM: 24,
    TicketPriority.HIGH: 4,
    TicketPriority.URGENT: 1,
}

SLA_RESOLUTION_TIME = {
    TicketPriority.LOW: 168,  # 7 days
    TicketPriority.MEDIUM: 72,  # 3 days
    TicketPriority.HIGH: 24,  # 1 day
    TicketPriority.URGENT: 4,  # 4 hours
}


class SupportTicketService:
    """
    Production-grade support ticket management service
    """

    def __init__(self, db: Session):
        """Initialize support ticket service"""
        self.db = db
        self.email_service = EmailService()

    # ===========================
    # TICKET CREATION
    # ===========================

    def create_ticket(
        self,
        user_id: int,
        subject: str,
        description: str,
        category: TicketCategory = TicketCategory.OTHER,
        priority: TicketPriority = TicketPriority.MEDIUM,
        metadata: Optional[Dict] = None
    ) -> SupportTicket:
        """
        Create new support ticket

        Args:
            user_id: User ID
            subject: Ticket subject
            description: Ticket description
            category: Ticket category
            priority: Priority level
            metadata: Additional metadata

        Returns:
            SupportTicket object
        """
        try:
            # Generate ticket number
            ticket_number = self._generate_ticket_number()

            # Calculate SLA due date
            sla_hours = SLA_RESOLUTION_TIME.get(priority, 24)
            sla_due_at = datetime.utcnow() + timedelta(hours=sla_hours)

            # Create ticket
            ticket = SupportTicket(
                ticket_number=ticket_number,
                user_id=user_id,
                subject=subject,
                description=description,
                category=category,
                priority=priority,
                status=TicketStatus.OPEN,
                metadata=metadata,
                sla_due_at=sla_due_at,
            )

            self.db.add(ticket)
            self.db.commit()
            self.db.refresh(ticket)

            # Send confirmation email
            self._send_ticket_created_email(ticket)

            logger.info(f"✓ Support ticket created: {ticket_number}")
            return ticket

        except Exception as e:
            logger.error(f"✗ Failed to create ticket: {e}")
            self.db.rollback()
            raise

    def _generate_ticket_number(self) -> str:
        """
        Generate unique ticket number

        Returns:
            Ticket number (e.g., TKT-202401-00001)
        """
        # Get current date
        now = datetime.utcnow()
        date_prefix = now.strftime("%Y%m")

        # Get count of tickets this month
        month_start = datetime(now.year, now.month, 1)
        count = self.db.query(SupportTicket).filter(
            SupportTicket.created_at >= month_start
        ).count()

        # Generate ticket number
        return f"TKT-{date_prefix}-{count + 1:05d}"

    # ===========================
    # TICKET MANAGEMENT
    # ===========================

    def get_ticket(self, ticket_id: int) -> Optional[SupportTicket]:
        """Get ticket by ID"""
        return self.db.query(SupportTicket).filter(
            SupportTicket.id == ticket_id
        ).first()

    def get_ticket_by_number(self, ticket_number: str) -> Optional[SupportTicket]:
        """Get ticket by ticket number"""
        return self.db.query(SupportTicket).filter(
            SupportTicket.ticket_number == ticket_number
        ).first()

    def list_user_tickets(
        self,
        user_id: int,
        status: Optional[TicketStatus] = None,
        limit: int = 50
    ) -> List[SupportTicket]:
        """
        List tickets for user

        Args:
            user_id: User ID
            status: Optional status filter
            limit: Max number of tickets

        Returns:
            List of tickets
        """
        query = self.db.query(SupportTicket).filter(
            SupportTicket.user_id == user_id
        )

        if status:
            query = query.filter(SupportTicket.status == status)

        return query.order_by(SupportTicket.created_at.desc()).limit(limit).all()

    def list_all_tickets(
        self,
        status: Optional[TicketStatus] = None,
        priority: Optional[TicketPriority] = None,
        assigned_to_id: Optional[int] = None,
        limit: int = 100
    ) -> List[SupportTicket]:
        """
        List all tickets (admin)

        Args:
            status: Optional status filter
            priority: Optional priority filter
            assigned_to_id: Optional assignee filter
            limit: Max number of tickets

        Returns:
            List of tickets
        """
        query = self.db.query(SupportTicket)

        if status:
            query = query.filter(SupportTicket.status == status)
        if priority:
            query = query.filter(SupportTicket.priority == priority)
        if assigned_to_id:
            query = query.filter(SupportTicket.assigned_to_id == assigned_to_id)

        return query.order_by(SupportTicket.created_at.desc()).limit(limit).all()

    def update_ticket_status(
        self,
        ticket_id: int,
        new_status: TicketStatus,
        admin_id: Optional[int] = None
    ) -> Optional[SupportTicket]:
        """
        Update ticket status

        Args:
            ticket_id: Ticket ID
            new_status: New status
            admin_id: Admin user ID

        Returns:
            Updated ticket
        """
        try:
            ticket = self.get_ticket(ticket_id)
            if not ticket:
                return None

            old_status = ticket.status
            ticket.status = new_status

            # Track resolution
            if new_status == TicketStatus.RESOLVED and not ticket.resolved_at:
                ticket.resolved_at = datetime.utcnow()

            # Track closure
            if new_status == TicketStatus.CLOSED and not ticket.closed_at:
                ticket.closed_at = datetime.utcnow()

            self.db.commit()
            self.db.refresh(ticket)

            # Send email notification
            if new_status != old_status:
                self._send_status_update_email(ticket, old_status, new_status)

            logger.info(f"✓ Ticket {ticket.ticket_number} status updated: {old_status.value} → {new_status.value}")
            return ticket

        except Exception as e:
            logger.error(f"✗ Failed to update ticket status: {e}")
            self.db.rollback()
            return None

    def assign_ticket(
        self,
        ticket_id: int,
        assigned_to_id: int
    ) -> Optional[SupportTicket]:
        """
        Assign ticket to admin/support user

        Args:
            ticket_id: Ticket ID
            assigned_to_id: Admin user ID

        Returns:
            Updated ticket
        """
        try:
            ticket = self.get_ticket(ticket_id)
            if not ticket:
                return None

            ticket.assigned_to_id = assigned_to_id

            # Update status if it's still open
            if ticket.status == TicketStatus.OPEN:
                ticket.status = TicketStatus.IN_PROGRESS

            self.db.commit()
            self.db.refresh(ticket)

            logger.info(f"✓ Ticket {ticket.ticket_number} assigned to user {assigned_to_id}")
            return ticket

        except Exception as e:
            logger.error(f"✗ Failed to assign ticket: {e}")
            self.db.rollback()
            return None

    def update_ticket_priority(
        self,
        ticket_id: int,
        new_priority: TicketPriority
    ) -> Optional[SupportTicket]:
        """
        Update ticket priority

        Args:
            ticket_id: Ticket ID
            new_priority: New priority

        Returns:
            Updated ticket
        """
        try:
            ticket = self.get_ticket(ticket_id)
            if not ticket:
                return None

            ticket.priority = new_priority

            # Recalculate SLA
            if not ticket.resolved_at:
                sla_hours = SLA_RESOLUTION_TIME.get(new_priority, 24)
                ticket.sla_due_at = datetime.utcnow() + timedelta(hours=sla_hours)

            self.db.commit()
            self.db.refresh(ticket)

            logger.info(f"✓ Ticket {ticket.ticket_number} priority updated to {new_priority.value}")
            return ticket

        except Exception as e:
            logger.error(f"✗ Failed to update ticket priority: {e}")
            self.db.rollback()
            return None

    # ===========================
    # TICKET MESSAGES
    # ===========================

    def add_message(
        self,
        ticket_id: int,
        user_id: int,
        message: str,
        is_internal: bool = False,
        is_automated: bool = False
    ) -> Optional[TicketMessage]:
        """
        Add message to ticket

        Args:
            ticket_id: Ticket ID
            user_id: User ID (sender)
            message: Message content
            is_internal: Internal note (not visible to user)
            is_automated: Automated message

        Returns:
            TicketMessage object
        """
        try:
            ticket = self.get_ticket(ticket_id)
            if not ticket:
                return None

            # Create message
            msg = TicketMessage(
                ticket_id=ticket_id,
                user_id=user_id,
                message=message,
                is_internal=1 if is_internal else 0,
                is_automated=1 if is_automated else 0,
            )

            self.db.add(msg)

            # Update ticket
            if not ticket.first_response_at and user_id != ticket.user_id:
                # First response from support
                ticket.first_response_at = datetime.utcnow()

            # Update status based on who is responding
            if user_id == ticket.user_id:
                # User replied
                if ticket.status == TicketStatus.WAITING_USER:
                    ticket.status = TicketStatus.WAITING_SUPPORT
            else:
                # Support replied
                if ticket.status == TicketStatus.WAITING_SUPPORT:
                    ticket.status = TicketStatus.WAITING_USER

            self.db.commit()
            self.db.refresh(msg)

            # Send email notification
            if not is_internal:
                self._send_new_message_email(ticket, msg)

            logger.info(f"✓ Message added to ticket {ticket.ticket_number}")
            return msg

        except Exception as e:
            logger.error(f"✗ Failed to add message: {e}")
            self.db.rollback()
            return None

    # ===========================
    # USER FEEDBACK
    # ===========================

    def add_user_rating(
        self,
        ticket_id: int,
        rating: int,
        feedback: Optional[str] = None
    ) -> bool:
        """
        Add user rating to resolved ticket

        Args:
            ticket_id: Ticket ID
            rating: Rating (1-5 stars)
            feedback: Optional feedback

        Returns:
            True if successful
        """
        try:
            ticket = self.get_ticket(ticket_id)
            if not ticket:
                return False

            if rating < 1 or rating > 5:
                return False

            ticket.user_rating = rating
            ticket.user_feedback = feedback

            self.db.commit()

            logger.info(f"✓ Rating added to ticket {ticket.ticket_number}: {rating}/5")
            return True

        except Exception as e:
            logger.error(f"✗ Failed to add rating: {e}")
            self.db.rollback()
            return False

    # ===========================
    # SLA MONITORING
    # ===========================

    def get_sla_breached_tickets(self) -> List[SupportTicket]:
        """
        Get tickets that have breached SLA

        Returns:
            List of tickets
        """
        return self.db.query(SupportTicket).filter(
            and_(
                SupportTicket.status.in_([
                    TicketStatus.OPEN,
                    TicketStatus.IN_PROGRESS,
                    TicketStatus.WAITING_USER,
                    TicketStatus.WAITING_SUPPORT
                ]),
                SupportTicket.sla_due_at < datetime.utcnow(),
                SupportTicket.sla_breached == 0
            )
        ).all()

    def mark_sla_breached(self) -> int:
        """
        Mark tickets as SLA breached

        Returns:
            Number of tickets marked
        """
        try:
            breached_tickets = self.get_sla_breached_tickets()

            for ticket in breached_tickets:
                ticket.sla_breached = 1

            self.db.commit()

            logger.warning(f"⚠️ {len(breached_tickets)} tickets breached SLA")
            return len(breached_tickets)

        except Exception as e:
            logger.error(f"✗ Failed to mark SLA breaches: {e}")
            self.db.rollback()
            return 0

    # ===========================
    # STATISTICS
    # ===========================

    def get_ticket_statistics(self, days: int = 30) -> Dict:
        """
        Get ticket statistics

        Args:
            days: Number of days to analyze

        Returns:
            Statistics dictionary
        """
        start_date = datetime.utcnow() - timedelta(days=days)

        total_tickets = self.db.query(SupportTicket).filter(
            SupportTicket.created_at >= start_date
        ).count()

        open_tickets = self.db.query(SupportTicket).filter(
            SupportTicket.status.in_([
                TicketStatus.OPEN,
                TicketStatus.IN_PROGRESS,
                TicketStatus.WAITING_USER,
                TicketStatus.WAITING_SUPPORT
            ])
        ).count()

        resolved_tickets = self.db.query(SupportTicket).filter(
            and_(
                SupportTicket.resolved_at >= start_date,
                SupportTicket.status == TicketStatus.RESOLVED
            )
        ).count()

        # Average resolution time
        resolved = self.db.query(SupportTicket).filter(
            and_(
                SupportTicket.resolved_at >= start_date,
                SupportTicket.resolved_at != None
            )
        ).all()

        avg_resolution_time = 0
        if resolved:
            times = [t.resolution_time_seconds for t in resolved if t.resolution_time_seconds]
            avg_resolution_time = sum(times) / len(times) if times else 0

        return {
            "period_days": days,
            "total_tickets": total_tickets,
            "open_tickets": open_tickets,
            "resolved_tickets": resolved_tickets,
            "average_resolution_hours": round(avg_resolution_time / 3600, 2),
            "sla_breach_count": self.db.query(SupportTicket).filter(
                SupportTicket.sla_breached == 1
            ).count(),
        }

    # ===========================
    # EMAIL NOTIFICATIONS
    # ===========================

    def _send_ticket_created_email(self, ticket: SupportTicket):
        """Send ticket creation confirmation email"""
        try:
            user = self.db.query(User).filter(User.id == ticket.user_id).first()
            if not user:
                return

            # TODO: Implement proper email template
            logger.info(f"📧 Would send ticket created email to {user.email}")

        except Exception as e:
            logger.error(f"Failed to send ticket created email: {e}")

    def _send_status_update_email(self, ticket: SupportTicket, old_status: TicketStatus, new_status: TicketStatus):
        """Send ticket status update email"""
        try:
            user = self.db.query(User).filter(User.id == ticket.user_id).first()
            if not user:
                return

            logger.info(f"📧 Would send status update email to {user.email}: {old_status.value} → {new_status.value}")

        except Exception as e:
            logger.error(f"Failed to send status update email: {e}")

    def _send_new_message_email(self, ticket: SupportTicket, message: TicketMessage):
        """Send new message notification email"""
        try:
            user = self.db.query(User).filter(User.id == ticket.user_id).first()
            if not user:
                return

            # Only send if message is from support (not from user themselves)
            if message.user_id != ticket.user_id:
                logger.info(f"📧 Would send new message email to {user.email}")

        except Exception as e:
            logger.error(f"Failed to send new message email: {e}")


def get_support_ticket_service(db: Session) -> SupportTicketService:
    """Get support ticket service instance"""
    return SupportTicketService(db)
